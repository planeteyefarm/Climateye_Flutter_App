import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../models/aqi.dart';
import '../models/building.dart';
import '../models/methane.dart';
import '../models/weather.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/map_preferences.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import '../utils/geo_utils.dart';
import '../utils/kml_export.dart';
import '../widgets/common.dart';
import '../widgets/dark_osm_tiles.dart';
import '../widgets/forecast_timeline_strip.dart';
import '../widgets/glass.dart';
import '../widgets/home_aqi_dashboard.dart';
import '../widgets/map_backed_route.dart';
import '../widgets/near_you_panel.dart';
import '../widgets/overview_cards.dart';
import '../widgets/weather_info_card.dart';
import '../widgets/weather_map_overlay.dart';
import '../widgets/weather_mode_bar.dart';
import '../widgets/weather_scale_bar.dart';
import 'analysis_screen.dart';
import 'home_aqi_details_screen.dart';
import 'login_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _map = MapController();
  final _api = ApiClient.instance;

  /// Shown only when the device location is unavailable; never labelled as GPS.
  static const _defaultCenter = LatLng(20.5937, 78.9629);
  /// Street-level close-up (~2–3 blocks, buildings/POIs), matching Screenshot 1.
  /// Neighbourhood scale: entire ~140 m AQI radius + nearby roads stay visible.
  static const _gpsZoom = 16.8;
  AnimationController? _gpsZoomAnim;
  final _center = ValueNotifier<LatLng>(_defaultCenter);
  LatLng? _gps;
  bool _openLocating = false;
  bool _openLocationFailed = false;
  bool _mapMovedByUser = false;
  /// Prevents re-entrant [MapController.move] while snapping home centre to GPS.
  bool _lockingHomeCenter = false;
  int _openLocateRequest = 0;
  bool _subscreenActive = false;

  /// Live AQI at [_locAqiFor], read exactly as the Live overview reads /aqi.
  LatLng? _locAqiFor;
  AqiRecord? _locAqi;
  String? _locAqiError;
  String? _locPlace;
  bool _locPlaceLoading = false;
  int _locPlaceRequest = 0;
  bool _locAqiLoading = false;
  bool _locCardOpen = false;
  int _locAqiRequest = 0;

  /// Radius analysis state (Near You feature)
  double _selectedRadius = 100.0;
  BuildingCollection? _radiusBuildings;
  bool _radiusLoading = false;
  String? _radiusError;
  WeatherSummary? _locWeather;
  bool _showNearYouCard = false;
  int _radiusRequest = 0;
  int _locWeatherRequest = 0;

  final _searchCtl = TextEditingController();
  final _searchLink = LayerLink();
  List<PlaceResult>? _searchResults;
  bool _searching = false;
  int _searchRequest = 0;

  /// false = OSM (default on launch); true = satellite with natural green treatment (Design 3).
  bool _satellite = false;

  // Weather mode controls & forecast timeline
  WeatherOverlayMode _weatherMode = WeatherOverlayMode.none;
  bool _is3dMode = false;
  DateTime? _selectedForecastDate;
  MonthlyWeatherResponse? _monthlyWeather;
  bool _monthlyWeatherLoading = false;
  String? _monthlyWeatherError;
  int _monthlyWeatherRequest = 0;
  List<WeatherFieldPoint> _weatherFieldPoints = [];
  bool _rainForecastMode = true;
  double _currentZoom = 5.0;

  // Interactive weather readout state (Website parity)
  LatLng? _readoutTappedCoordinate;
  LatLng? _readoutHoverCoordinate;
  Offset? _readoutHoverPosition;

  // Analysis workspace sheet (UI state only).
  _SheetSize _sheet = _SheetSize.collapsed;
  double? _dragHeight;
  _SheetTab _tab = _SheetTab.area;
  _AnalysisType _analysisType = _AnalysisType.aqi;
  bool _legendOpen = true;
  bool _showMethaneOverlay = true;
  bool _showPlumes = true;
  /// Null until toggled; defaults to open on wide layouts.
  bool? _aqiLegendOpen;

  /// Arguments of the latest Run Analysis; [_analysisRun] keys a fresh
  /// [AnalysisPanel] per run.
  AnalysisArgs? _analysis;
  int _analysisRun = 0;

  bool _isDrawing = false;
  final List<LatLng> _draft = [];
  AreaGeometry? _geometry;
  String? _kmlName;

  /// True only while [_geometry] is a polygon completed through Draw Area.
  bool _drawnByUser = false;
  bool _savingKml = false;
  bool _locating = false;
  String? _locationNote;
  int _locateRequest = 0;

  late DateTime _endDate = today();
  late DateTime _startDate = today().subtract(const Duration(days: 7));

  bool _methaneLoading = false;
  MethaneTiles? _methaneTiles;
  List<MethanePlume> _plumes = [];
  String? _methaneNote;

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.card,
      ));
  }

  @override
  void initState() {
    super.initState();
    MapPreferences.loadIsSatellite().then((val) {
      if (mounted && val != _satellite) {
        setState(() => _satellite = val);
      }
    });
  }

  void _setSatellite(bool value) {
    if (_satellite == value) return;
    setState(() => _satellite = value);
    MapPreferences.saveIsSatellite(value);
  }

  void _toggleSatellite() {
    _setSatellite(!_satellite);
  }

  @override
  void dispose() {
    _gpsZoomAnim?.dispose();
    _center.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _locateOnOpen({bool recenter = false}) async {
    final request = ++_openLocateRequest;
    setState(() {
      _openLocating = true;
      _openLocationFailed = false;
    });
    final result = await LocationService.instance.currentLocation();
    if (!mounted || request != _openLocateRequest) return;
    final pos = result.position;
    setState(() {
      _openLocating = false;
      _openLocationFailed = pos == null;
      if (pos != null) {
        _gps = pos;
      }
    });
    if (pos != null) {
      final untouched = !_mapMovedByUser && _geometry == null;
      _selectedRadius = 100.0;
      // Keep Design 1→5 clean: Near You stays off until the user opens it.
      _showNearYouCard = false;
      if (!_isDrawing && (recenter || untouched)) {
        // AQI gauge is map-anchored at GPS — centre the coordinate itself.
        _moveToGps(pos);
      }
      if (pos != _locAqiFor || _locAqiError != null) _loadLocationAqi(pos);
      _loadLocationWeather(pos, _selectedForecastDate);
      _loadMonthlyWeather(pos, _selectedForecastDate ?? DateTime.now());
    } else {
      _loadLocationWeather(_defaultCenter, _selectedForecastDate);
      _loadMonthlyWeather(_defaultCenter, _selectedForecastDate ?? DateTime.now());
      _snack(
        '${result.error} Showing the default map view, not your location. '
        'Allow location access for this site in your browser or device '
        'settings, then use the retry button on the map.',
        error: true,
      );
    }
  }

  Future<void> _loadLocationAqi(LatLng pos) async {
    final request = ++_locAqiRequest;
    setState(() {
      _locAqiFor = pos;
      _locAqi = null;
      _locAqiError = null;
      _locAqiLoading = true;
    });
    // Resolve place name independently so the badge can load / fall back
    // without waiting on /aqi.
    unawaited(_resolvePlaceName(pos));
    try {
      final record = AqiRecord.fromJson(await _api.fetchAqi(pos.latitude, pos.longitude));
      if (!mounted || request != _locAqiRequest) return;
      setState(() => _locAqi = record);
    } catch (e) {
      if (!mounted || request != _locAqiRequest) return;
      setState(() => _locAqiError = e.toString());
    } finally {
      if (mounted && request == _locAqiRequest) setState(() => _locAqiLoading = false);
    }
  }

  Future<void> _resolvePlaceName(LatLng pos) async {
    final request = ++_locPlaceRequest;
    if (mounted) {
      setState(() {
        _locPlaceLoading = true;
      });
    }
    String? name;
    try {
      name = await _api.fetchPlaceName(pos.latitude, pos.longitude);
    } catch (_) {
      name = null;
    }
    if (!mounted || request != _locPlaceRequest) return;
    setState(() {
      _locPlace = (name != null && name.trim().isNotEmpty) ? name.trim() : null;
      _locPlaceLoading = false;
    });
  }

  Future<void> _loadLocationWeather(LatLng pos, [DateTime? date]) async {
    final request = ++_locWeatherRequest;
    try {
      final weather = await _api.fetchWeather(pos.latitude, pos.longitude, date);
      if (!mounted || request != _locWeatherRequest) return;
      setState(() => _locWeather = weather);
      _updateWeatherFieldPoints(pos, weather);
    } catch (_) {
      if (!mounted || request != _locWeatherRequest) return;
    }
  }

  Future<void> _loadMonthlyWeather(LatLng pos, DateTime date) async {
    final request = ++_monthlyWeatherRequest;
    setState(() {
      _monthlyWeatherLoading = true;
      _monthlyWeatherError = null;
    });

    try {
      final res = await _api.fetchMonthlyWeatherFull(
        pos.latitude,
        pos.longitude,
        date.year,
        date.month,
      );
      if (!mounted || request != _monthlyWeatherRequest) return;
      setState(() {
        _monthlyWeather = res;
        _monthlyWeatherLoading = false;
      });
    } catch (e) {
      if (!mounted || request != _monthlyWeatherRequest) return;
      _loadMonthlyFallback(pos, date, request);
    }
  }

  Future<void> _loadMonthlyFallback(LatLng pos, DateTime date, int request) async {
    try {
      final hourly = await _api.fetchHourlyWeather(pos.latitude, pos.longitude, date);
      if (!mounted || request != _monthlyWeatherRequest) return;

      final Map<String, List<HourlyWeather>> byDay = {};
      for (final h in hourly) {
        if (h.date != null) {
          final key = ymd(h.date!);
          byDay.putIfAbsent(key, () => []).add(h);
        }
      }

      final records = <MonthlyWeatherDay>[];
      byDay.forEach((k, list) {
        final temps = list.map((e) => e.temperature).whereType<double>().toList();
        final maxT = temps.isNotEmpty ? temps.reduce(math.max) : null;
        final minT = temps.isNotEmpty ? temps.reduce(math.min) : null;
        final midday = list.firstWhere(
          (e) => e.date?.hour == 12,
          orElse: () => list.first,
        );
        records.add(MonthlyWeatherDay(
          date: midday.date,
          condition: midday.condition,
          tempMax: maxT,
          tempMin: minT,
          category: categoryFromCondition(midday.condition),
        ));
      });

      final sum = {'sunny': 0, 'partly-cloudy': 0, 'cloudy': 0, 'rainy': 0, 'snowy': 0};
      for (final r in records) {
        final cat = categoryFromCondition(r.condition);
        if (sum.containsKey(cat)) {
          sum[cat] = (sum[cat] ?? 0) + 1;
        }
      }

      setState(() {
        _monthlyWeather = MonthlyWeatherResponse(
          year: date.year,
          month: date.month,
          dailyRecords: records,
          summary: sum,
        );
        _monthlyWeatherLoading = false;
      });
    } catch (err) {
      if (!mounted || request != _monthlyWeatherRequest) return;
      setState(() {
        _monthlyWeatherLoading = false;
        _monthlyWeatherError = err.toString();
      });
    }
  }

  void _updateWeatherFieldPoints(LatLng center, WeatherSummary? current) {
    final baseTemp = current?.temperature ?? 28.0;
    final baseRain = current?.precipitation ?? 0.0;
    final baseWind = current?.windSpeed ?? 14.0;

    final points = <WeatherFieldPoint>[
      WeatherFieldPoint(
        location: center,
        temperature: baseTemp,
        precipitation: baseRain,
        windSpeed: baseWind,
        windDirection: 240,
      ),
      WeatherFieldPoint(
        location: const LatLng(5.5, -0.2),
        temperature: baseTemp - 1.0,
        precipitation: 3.5,
        windSpeed: 18.0,
        windDirection: 210,
      ),
      WeatherFieldPoint(
        location: const LatLng(-4.0, 21.7),
        temperature: baseTemp + 0.8,
        precipitation: 1.2,
        windSpeed: 12.0,
        windDirection: 180,
      ),
      WeatherFieldPoint(
        location: const LatLng(19.0760, 72.8777),
        temperature: baseTemp,
        precipitation: baseRain,
        windSpeed: baseWind,
        windDirection: 270,
      ),
      WeatherFieldPoint(
        location: const LatLng(-5.0, 160.0),
        temperature: baseTemp + 1.5,
        precipitation: 0.0,
        windSpeed: 24.0,
        windDirection: 90,
      ),
      WeatherFieldPoint(
        location: const LatLng(25.0, 45.0),
        temperature: baseTemp + 4.5,
        precipitation: 0.0,
        windSpeed: 15.0,
        windDirection: 315,
      ),
      WeatherFieldPoint(
        location: const LatLng(38.0, 23.0),
        temperature: baseTemp - 5.5,
        precipitation: 0.0,
        windSpeed: 16.0,
        windDirection: 340,
      ),
      WeatherFieldPoint(
        location: const LatLng(40.0, 116.0),
        temperature: baseTemp - 8.0,
        precipitation: 0.0,
        windSpeed: 13.0,
        windDirection: 45,
      ),
      WeatherFieldPoint(
        location: const LatLng(-33.0, 151.0),
        temperature: baseTemp - 3.0,
        precipitation: 0.5,
        windSpeed: 20.0,
        windDirection: 135,
      ),
    ];

    setState(() {
      _weatherFieldPoints = points;
    });
  }

  void _toggle3dMode() {
    setState(() {
      _is3dMode = !_is3dMode;
    });
    if (_is3dMode) {
      _map.rotate(25.0);
    } else {
      _map.rotate(0.0);
    }
  }

  void _onSelectForecastDate(DateTime date) {
    setState(() {
      _selectedForecastDate = date;
    });
    final center = _gps ?? _center.value;
    _loadLocationWeather(center, date);
  }

  Future<void> _loadRadiusBuildings(LatLng pos, double radiusMeters) async {
    final request = ++_radiusRequest;
    setState(() {
      _radiusLoading = true;
      _radiusError = null;
    });
    try {
      final collection = await _api.fetchBuildingsForRadius(
        center: pos,
        radiusMeters: radiusMeters,
      );
      if (!mounted || request != _radiusRequest) return;
      setState(() {
        _radiusBuildings = collection;
        _radiusLoading = false;
      });
    } catch (e) {
      if (!mounted || request != _radiusRequest) return;
      setState(() {
        _radiusError = e.toString();
        _radiusLoading = false;
      });
    }
  }

  void _onSelectRadius(double radiusMeters) {
    setState(() {
      _selectedRadius = radiusMeters;
      _showNearYouCard = true;
    });
    if (_gps != null) {
      final bounds = latLngBoundsForRadius(_gps!, radiusMeters);
      _map.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(48),
        maxZoom: 17,
      ));
      _loadRadiusBuildings(_gps!, radiusMeters);
    }
  }

  Future<void> _searchPlaces(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final request = ++_searchRequest;
    setState(() => _searching = true);
    try {
      final results = await _api.searchPlaces(q);
      if (!mounted || request != _searchRequest) return;
      setState(() => _searchResults = results);
    } catch (_) {
      if (!mounted || request != _searchRequest) return;
      _snack('Place search failed. Check your connection and try again.', error: true);
    } finally {
      if (mounted && request == _searchRequest) setState(() => _searching = false);
    }
  }

  void _goToPlace(PlaceResult p) {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchResults = null;
      _searchCtl.text = p.name;
    });
    _mapMovedByUser = true;
    final pos = LatLng(p.latitude, p.longitude);
    _map.move(pos, 11);
    _loadLocationWeather(pos, _selectedForecastDate);
    _loadMonthlyWeather(pos, _selectedForecastDate ?? DateTime.now());
  }

  void _clearSearch() {
    ++_searchRequest;
    setState(() {
      _searchCtl.clear();
      _searchResults = null;
      _searching = false;
    });
  }

  void _moveToGps(LatLng pos, {double? zoom, bool animate = true}) {
    final targetZoom = zoom ?? _gpsZoom;
    if (!animate || !mounted) {
      _map.move(pos, targetZoom);
      return;
    }
    _gpsZoomAnim?.stop();
    _gpsZoomAnim?.dispose();
    final startCenter = _map.camera.center;
    final startZoom = _map.camera.zoom;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _gpsZoomAnim = controller;
    final curved =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);
    void tick() {
      if (!mounted) return;
      final t = curved.value;
      final lat =
          startCenter.latitude + (pos.latitude - startCenter.latitude) * t;
      final lng =
          startCenter.longitude + (pos.longitude - startCenter.longitude) * t;
      final z = startZoom + (targetZoom - startZoom) * t;
      _lockingHomeCenter = true;
      _map.move(LatLng(lat, lng), z);
      _lockingHomeCenter = false;
    }

    controller.addListener(tick);
    controller.forward().whenComplete(() {
      if (!mounted) return;
      controller.removeListener(tick);
      _map.move(pos, targetZoom);
      if (identical(_gpsZoomAnim, controller)) {
        _gpsZoomAnim = null;
        controller.dispose();
      }
    });
  }

  void _recenter() {
    if (_gps == null) {
      _locateOnOpen(recenter: true);
      return;
    }
    _moveToGps(_gps!);
  }

  Future<void> _openHomeAqiDetails(HomeAqiDetailsMode mode) async {
    final gps = _gps;
    if (gps == null) return;
    setState(() => _subscreenActive = true);
    await Navigator.of(context).push(
      MapBackedPageRoute(
        builder: (_) => HomeAqiDetailsScreen(
          latitude: gps.latitude,
          longitude: gps.longitude,
          mode: mode,
          initialRecord: _locAqi,
          placeName: _locPlace,
          isSatellite: _satellite,
        ),
      ),
    );
    if (mounted) {
      setState(() => _subscreenActive = false);
    }
  }

  void _startDrawing() {
    setState(() {
      _isDrawing = true;
      _draft.clear();
      _geometry = null;
      _kmlName = null;
      _drawnByUser = false;
      _locationNote = null;
    });
    _locateForDrawing();
  }

  Future<void> _locateForDrawing() async {
    final request = ++_locateRequest;
    setState(() => _locating = true);
    final result = await LocationService.instance.currentLocation();
    if (!mounted || request != _locateRequest) return;
    setState(() => _locating = false);
    if (!_isDrawing) return;
    final pos = result.position;
    if (pos != null) {
      _map.move(pos, 15);
      setState(() {
        _gps = pos;
        _locationNote = 'Location found! You can now draw your area on the map.';
      });
    } else {
      _snack('${result.error} You can still draw the area manually.', error: true);
    }
  }

  void _cancelLocate() {
    _locateRequest++;
    _locating = false;
  }

  void _finishDrawing() {
    final geom = AreaGeometry.fromVertices(_draft);
    if (!geom.isValid) {
      _snack('Place at least 3 distinct points to create an area', error: true);
      return;
    }
    setState(() {
      _cancelLocate();
      _geometry = geom;
      _drawnByUser = true;
      _isDrawing = false;
      _draft.clear();
    });
  }

  void _cancelDrawing() => setState(() {
        _cancelLocate();
        _isDrawing = false;
        _draft.clear();
      });

  Future<void> _downloadKml() async {
    final geom = _geometry;
    if (geom == null || !_drawnByUser || !geom.isValid) return;
    setState(() => _savingKml = true);
    try {
      final fileName = kmlFileName(DateTime.now());
      final bytes = Uint8List.fromList(utf8.encode(buildPolygonKml(geom.ring)));
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/vnd.google-earth.kml+xml',
        dialogTitle: 'Save drawn area as KML',
        type: FileType.custom,
        allowedExtensions: const ['kml'],
      );
      if (!mounted) return;
      // Web triggers a browser download and always returns null; on other
      // platforms null means the user cancelled the save dialog.
      if (kIsWeb) {
        _snack('Downloading $fileName');
      } else if (saved != null) {
        _snack('Saved $fileName');
      }
    } catch (e) {
      if (mounted) _snack('Could not save KML: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingKml = false);
    }
  }

  Future<void> _uploadKml() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['kml', 'kmz'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      final geom = parseKmlOrKmz(file.name, bytes);
      setState(() {
        _cancelLocate();
        _geometry = geom;
        _kmlName = file.name;
        _drawnByUser = false;
        _isDrawing = false;
        _draft.clear();
      });
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(geom.ring),
        padding: const EdgeInsets.all(48),
      ));
    } catch (e) {
      _snack('Could not load KML: $e', error: true);
    }
  }

  void _clear() => setState(() {
        _cancelLocate();
        _geometry = null;
        _kmlName = null;
        _drawnByUser = false;
        _draft.clear();
        _isDrawing = false;
        _methaneTiles = null;
        _plumes = [];
        _methaneNote = null;
      });

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: start ? _endDate : today(),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
      } else {
        _endDate = picked;
        if (_startDate.isAfter(_endDate)) _startDate = _endDate;
      }
    });
  }

  void _analyse() {
    final geom = _geometry;
    if (geom == null || !geom.isValid) {
      _snack('Draw an area or upload a KML file first', error: true);
      return;
    }
    final c = geom.centroid;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _analysis = AnalysisArgs(
        latitude: c.latitude,
        longitude: c.longitude,
        startDate: _startDate,
        endDate: _endDate,
      );
      _analysisRun++;
      _tab = _analysisType == _AnalysisType.weather ? _SheetTab.weather : _SheetTab.airQuality;
      _sheet = _SheetSize.full;
    });
  }

  Future<void> _analyseMethane() async {
    final geom = _geometry;
    if (geom == null || !geom.isValid) {
      _snack('Draw an area or upload a KML file first', error: true);
      return;
    }
    setState(() {
      _methaneLoading = true;
      _methaneNote = null;
    });
    try {
      final catalog = await _api.fetchMethaneCatalog();
      var start = _startDate, end = _endDate;
      final cs = catalog.coverageStart, ce = catalog.coverageEnd;
      String? note;
      if (cs != null && ce != null) {
        if (start.isAfter(ce) || end.isBefore(cs)) {
          throw Exception('Selected dates are outside the methane archive '
              '(${ymd(cs)} to ${ymd(ce)}). Choose dates within that range.');
        }
        if (start.isBefore(cs)) start = cs;
        if (end.isAfter(ce)) end = ce;
        if (start != _startDate || end != _endDate) {
          note = 'Dates limited to archive coverage: ${ymd(start)} – ${ymd(end)}';
        }
      }
      final bounds = geom.boundsString;
      final results = await Future.wait([
        _api.fetchMethanePlumes(bounds, start, end),
        _api.fetchMethaneTiles(bounds, start, end),
      ]);
      if (!mounted) return;
      final plumes = results[0] as List<MethanePlume>;
      setState(() {
        _plumes = plumes;
        _methaneTiles = results[1] as MethaneTiles;
        _methaneNote = [
          ?note,
          '${plumes.length} plume${plumes.length == 1 ? '' : 's'} found',
        ].join(' · ');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _methaneTiles = null;
        _plumes = [];
      });
      _snack('Methane analysis failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _methaneLoading = false);
    }
  }

  void _showPlume(MethanePlume p) {
    String f(double? v, [int d = 1]) => v == null ? '—' : v.toStringAsFixed(d);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Methane plume',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _kv('Enhancement', '${f(p.enhancement)} ppm·m'),
            _kv('Confidence', p.confidence ?? '—'),
            _kv('Observed', p.observedAt ?? '—'),
            _kv('Wind', '${f(p.windSpeed)} m/s @ ${f(p.windDirection, 0)}°'),
            _kv('Max plume length', '${f(p.plumeLenMax, 0)} m'),
            _kv('Location',
                '${p.point.latitude.toStringAsFixed(4)}, ${p.point.longitude.toStringAsFixed(4)}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(color: AppColors.textMuted))),
          Expanded(child: Text(v)),
        ]),
      );

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  // ===================== Layout =====================

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static const _collapsedH = 64.0;
  static const _railW = 52.0;

  /// Design 1: map + search while GPS is resolving or unavailable.
  bool get _homeFetching =>
      !_isDrawing && _sheet == _SheetSize.collapsed && (_openLocating || _gps == null);

  /// Design 5: GPS acquired — show central AQI (loading / data / error).
  bool get _homeDashboard =>
      !_isDrawing && _sheet == _SheetSize.collapsed && _gps != null && !_openLocating;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: LightOsmTileLayer.background,
      drawer: _navDrawer(),
      body: LayoutBuilder(builder: (context, c) {
        final mq = MediaQuery.of(context);
        final wide = c.maxWidth >= 900;
        final compact = c.maxWidth < 600;
        final collapsedH = wide ? _collapsedH : 46.0;
        final showAdvancedPanels = !_homeFetching && !_homeDashboard;
        final bottomNavH = 60.0 + mq.padding.bottom + (_weatherMode != WeatherOverlayMode.none ? 44.0 : 0.0);
        if (_subscreenActive) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: _mapView()),
            ],
          );
        }
        return Stack(children: [
          Positioned.fill(child: _mapView()),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_homeFetching || _homeDashboard)
                      _homeTopBar(wide: wide, compact: compact)
                    else
                      _header(wide: wide, compact: compact),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_isDrawing && wide && !_homeFetching)
                            SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!_homeDashboard) ...[
                                    _gpsChip(),
                                    const SizedBox(height: 10),
                                  ],
                                  _toolRail(),
                                ],
                              ),
                            )
                          else if (wide)
                            const SizedBox(width: _railW),
                          const Spacer(),
                          // Home dashboard: controls sit top-right (see Positioned
                          // below) so they clear the centre location circle.
                          if (!_homeFetching && !_homeDashboard)
                            SingleChildScrollView(
                              child: _mapControls(
                                wide: wide,
                                legendFits: _sheet == _SheetSize.collapsed ||
                                    (wide && (c.maxWidth - _sheetWidth(c, wide)) / 2 >= 200),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: _isDrawing
                          ? 190
                          : (_homeFetching || _homeDashboard)
                              ? mq.padding.bottom + 24
                              : (wide
                                  ? collapsedH + 12
                                  : bottomNavH),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _sheetView(c, wide, mq, hidden: _isDrawing || _sheet == _SheetSize.collapsed),
          // Map controls above the location circle while home AQI is showing.
          if (_homeDashboard)
            Positioned(
              top: mq.padding.top + (compact ? 62 : 70),
              right: 12,
              child: _mapControls(wide: wide, legendFits: false),
            ),
          // GPS resolving: subtle cyan pulse at map centre — no loading text.
          if (_homeFetching && !_openLocationFailed)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: HomeGpsLocatingIndicator()),
              ),
            ),
          // Permission / GPS failure: silent until user taps retry (no banner copy).
          if (_homeFetching && _openLocationFailed)
            Positioned(
              left: 16,
              right: 16,
              bottom: mq.padding.bottom + 28,
              child: Center(
                child: HomeGpsRetryChip(
                  onRetry: () => _locateOnOpen(recenter: true),
                ),
              ),
            ),
          // Design 5 — AQI gauge fixed at screen centre; History/Prediction bar
          // after AQI loads. Gauge taps open a separate details page.
          if (_homeDashboard) ...[
            Positioned.fill(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  HomeAqiGauge(
                    aqi: _locAqi?.aqi,
                    category: _locAqi?.aqi != null
                        ? aqiCategory(_locAqi!.aqi!)
                        : null,
                    loading: _locAqiLoading,
                    error: _locAqiError,
                    onRetry:
                        _gps == null ? null : () => _loadLocationAqi(_gps!),
                    onTap: _locAqi == null
                        ? null
                        : () =>
                            _openHomeAqiDetails(HomeAqiDetailsMode.overview),
                    size: 150,
                  ),
                  // Above AQI radius: pulse while geocoding, then floating label.
                  Transform.translate(
                    offset: const Offset(0, -178),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 56),
                      child: IgnorePointer(
                        child: _locPlaceLoading
                            ? const HomeGpsLocatingIndicator(size: 72)
                            : (_locPlace != null && _locPlace!.isNotEmpty
                                ? HomeLocationNameChip(name: _locPlace!)
                                : const SizedBox.shrink()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_locAqi != null && !_locAqiLoading)
              Positioned(
                left: 12,
                right: 12,
                bottom: mq.padding.bottom + 16,
                child: Center(
                  child: HomeHistoryPredictionBar(
                    selectedMode: 'history',
                    accentColor: const Color(0xFF02A78D),
                    onHistory: () =>
                        _openHomeAqiDetails(HomeAqiDetailsMode.history),
                    onPrediction: () =>
                        _openHomeAqiDetails(HomeAqiDetailsMode.prediction),
                  ),
                ),
              )
            else if (_locAqiError != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: mq.padding.bottom + 16,
                child: HomePollutantBar(
                  record: null,
                  placeName: _locPlace,
                  aqiError: _locAqiError,
                  onRetryAqi:
                      _gps == null ? null : () => _loadLocationAqi(_gps!),
                ),
              ),
          ],
          if (!_isDrawing && wide && showAdvancedPanels)
            Positioned(
              left: 16,
              top: 72,
              child: WeatherInfoCard(
                maxWidth: 340.0,
                weather: _locWeather,
                monthlyResponse: _monthlyWeather,
                loading: _monthlyWeatherLoading,
                error: _monthlyWeatherError,
                compact: false,
                searchWidget: _searchField(compact: false),
              ),
            ),
          if (wide && _gps != null && _showNearYouCard && !_isDrawing && _sheet == _SheetSize.collapsed)
            Positioned(
              top: 72,
              right: 16,
              child: NearYouPanel(
                maxWidth: 290.0,
                initiallyMinimized: false,
                selectedRadius: _selectedRadius,
                onSelectRadius: _onSelectRadius,
                aqiRecord: _locAqi,
                weatherSummary: _locWeather,
                buildingCollection: _radiusBuildings,
                loading: _radiusLoading,
                error: _radiusError,
                onClose: () => setState(() => _showNearYouCard = false),
              ),
            ),
          if (!_isDrawing && !wide && showAdvancedPanels)
            Positioned(
              left: 12,
              top: mq.padding.top + 52,
              child: WeatherInfoCard(
                maxWidth: math.min(275.0, c.maxWidth - 72),
                weather: _locWeather,
                monthlyResponse: _monthlyWeather,
                loading: _monthlyWeatherLoading,
                error: _monthlyWeatherError,
                compact: true,
                searchWidget: _searchField(compact: true),
              ),
            ),
          if (!_isDrawing &&
              !wide &&
              _gps != null &&
              _showNearYouCard &&
              _sheet == _SheetSize.collapsed)
            Positioned(
              left: 12,
              top: mq.padding.top + (_homeDashboard || _homeFetching ? 64 : 160),
              child: NearYouPanel(
                maxWidth: math.min(265.0, c.maxWidth - 72),
                initiallyMinimized: true,
                selectedRadius: _selectedRadius,
                onSelectRadius: _onSelectRadius,
                aqiRecord: _locAqi,
                weatherSummary: _locWeather,
                buildingCollection: _radiusBuildings,
                loading: _radiusLoading,
                error: _radiusError,
                onClose: () => setState(() => _showNearYouCard = false),
              ),
            ),
          if (!_isDrawing && _sheet == _SheetSize.collapsed && showAdvancedPanels)
            Positioned(
              right: 12,
              bottom: wide
                  ? mq.padding.bottom + 8 + collapsedH + 8
                  : bottomNavH + 8,
              child: _coordsChip(compact: !wide),
            ),
          if (!_isDrawing &&
              _weatherMode != WeatherOverlayMode.none &&
              _sheet == _SheetSize.collapsed &&
              showAdvancedPanels)
            Positioned(
              left: 12,
              right: 12,
              bottom: 60 + mq.padding.bottom + 6,
              child: Center(
                child: WeatherScaleBar(
                  mode: _weatherMode,
                  rainForecastMode: _rainForecastMode,
                  onToggleRainForecast: (v) => setState(() => _rainForecastMode = v),
                ),
              ),
            ),
          if (!_isDrawing && _sheet == _SheetSize.collapsed && showAdvancedPanels)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: const Color.fromRGBO(12, 14, 24, 0.98),
                padding: EdgeInsets.only(bottom: mq.padding.bottom),
                child: ForecastTimelineStrip(
                  dailyRecords: _monthlyWeather?.dailyRecords ?? [],
                  selectedDate: _selectedForecastDate,
                  onSelectDate: _onSelectForecastDate,
                  loading: _monthlyWeatherLoading,
                ),
              ),
            ),
          // OSM attribution — always visible on the dark free basemap.
          if (!_satellite && !_isDrawing)
            Positioned(
              right: 10,
              bottom: mq.padding.bottom + 8,
              child: const OsmAttribution(),
            ),
          if (_isDrawing) _drawingDock(c, mq),
          if (_searchResults != null)
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _searchLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                offset: const Offset(0, 6),
                child: _searchResultsView(wide ? 360 : math.min(320.0, c.maxWidth - 24)),
              ),
            ),
        ]);
      }),
    );
  }

  /// Compact Design 1/5 chrome: light glass menu, search, locate.
  Widget _homeTopBar({required bool wide, required bool compact}) {
    final size = compact ? 40.0 : 44.0;
    Widget lightIconBtn({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.88),
              border: Border.all(color: LightOsmTileLayer.accent.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon,
                size: size * 0.45,
                color: onPressed == null
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF0F172A)),
          ),
        ),
      );
    }

    return Row(children: [
      Tooltip(
        message: 'Menu',
        child: lightIconBtn(
          icon: Icons.menu,
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: _lightSearchField()),
      const SizedBox(width: 8),
      Tooltip(
        message: _gps != null ? 'Centre on my location' : 'Find my location',
        child: lightIconBtn(
          icon: Icons.my_location,
          tooltip: 'Locate',
          onPressed: _openLocating ? null : _recenter,
        ),
      ),
    ]);
  }

  Widget _lightSearchField() {
    return CompositedTransformTarget(
      link: _searchLink,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 42,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: LightOsmTileLayer.accent.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: LightOsmTileLayer.accent),
                  )
                : const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtl,
                textInputAction: TextInputAction.search,
                onSubmitted: _searchPlaces,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A)),
                cursorColor: LightOsmTileLayer.accent,
                decoration: const InputDecoration(
                  hintText: 'Search location…',
                  hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            if (_searchCtl.text.isNotEmpty || _searchResults != null)
              IconButton(
                tooltip: 'Clear search',
                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close, size: 17, color: Color(0xFF64748B)),
                onPressed: _clearSearch,
              ),
          ]),
        ),
      ),
    );
  }

  // ---------- Map ----------

  Widget _mapView() {
    final tiles = _methaneTiles;
    final geom = _geometry;
    return MouseRegion(
      onHover: (event) {
        if (_weatherMode != WeatherOverlayMode.none) {
          try {
            final pt = _map.camera.screenOffsetToLatLng(event.localPosition);
            setState(() {
              _readoutHoverPosition = event.localPosition;
              _readoutHoverCoordinate = pt;
            });
          } catch (_) {}
        }
      },
      onExit: (_) {
        if (_readoutHoverPosition != null || _readoutHoverCoordinate != null) {
          setState(() {
            _readoutHoverPosition = null;
            _readoutHoverCoordinate = null;
          });
        }
      },
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _defaultCenter,
          initialZoom: 5,
          backgroundColor: LightOsmTileLayer.background,
          // Home mode: zoom around GPS under the fixed centre gauge; no pan.
          interactionOptions: InteractionOptions(
            flags: _homeDashboard
                ? (InteractiveFlag.pinchZoom |
                    InteractiveFlag.scrollWheelZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.doubleTapDragZoom)
                : InteractiveFlag.all,
            pinchZoomWinGestures: _homeDashboard
                ? MultiFingerGesture.pinchZoom
                : (MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove),
          ),
          onTap: (_, point) {
            if (_isDrawing) {
              setState(() => _draft.add(point));
            } else if (_weatherMode != WeatherOverlayMode.none) {
              setState(() => _readoutTappedCoordinate = point);
            }
          },
          onMapReady: _locateOnOpen,
          onPositionChanged: (camera, hasGesture) {
            _center.value = camera.center;
            _currentZoom = camera.zoom;
            if (hasGesture) _mapMovedByUser = true;
            // Keep GPS under the fixed screen-centre gauge while zooming.
            if (_homeDashboard &&
                _gps != null &&
                !_lockingHomeCenter) {
              final g = _gps!;
              if ((camera.center.latitude - g.latitude).abs() > 1e-6 ||
                  (camera.center.longitude - g.longitude).abs() > 1e-6) {
                _lockingHomeCenter = true;
                _map.move(g, camera.zoom);
                _lockingHomeCenter = false;
              }
            }
          },
        ),
      children: [
        // Basemap: Satellite with natural green treatment (Design 3) or natural light OSM.
        if (_satellite) ...[
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0x280D4720),
              BlendMode.color,
            ),
            child: TileLayer(
              urlTemplate: TileUrls.satellite,
              userAgentPackageName: 'com.climateeye.climateeye',
            ),
          ),
          TileLayer(
            urlTemplate: TileUrls.labels,
            userAgentPackageName: 'com.climateeye.climateeye',
          ),
        ] else
          const LightOsmTileLayer(),
        if (tiles?.tileUrl != null && _showMethaneOverlay)
          TileLayer(
            urlTemplate: tiles!.tileUrl!,
            userAgentPackageName: 'com.climateeye.climateeye',
          ),
        ...WeatherMapOverlay.buildLayers(
          mode: _weatherMode,
          points: _weatherFieldPoints,
          zoom: _currentZoom,
          selectedDate: _selectedForecastDate,
          initialCenter: _gps ?? _defaultCenter,
          initialTemperature: _locWeather?.temperature,
          initialPrecipitation: _locWeather?.precipitation,
          initialWindSpeed: _locWeather?.windSpeed,
          initialWindDirection: 180.0,
          rainForecastMode: _rainForecastMode,
          tappedCoordinate: _readoutTappedCoordinate,
          hoverCoordinate: _readoutHoverCoordinate,
          hoverScreenPosition: _readoutHoverPosition,
          onDismissReadout: () => setState(() => _readoutTappedCoordinate = null),
        ),
        if (geom != null) ...[
          PolylineLayer(polylines: [
            Polyline(
              points: [...geom.ring, geom.ring.first],
              color: AppColors.cyan.withValues(alpha: 0.28),
              strokeWidth: 10,
            ),
          ]),
          PolygonLayer(polygons: [
            Polygon(
              points: geom.ring,
              color: AppColors.mint.withValues(alpha: 0.22),
              borderColor: AppColors.cyan,
              borderStrokeWidth: 2.5,
            ),
          ]),
          MarkerLayer(markers: [
            for (final p in _distinctRing(geom.ring))
              Marker(point: p, width: 14, height: 14, child: _vertexDot()),
            Marker(
              point: geom.centroid,
              width: 26,
              height: 26,
              child: const Icon(Icons.add_circle_outline, size: 22, color: AppColors.softMint),
            ),
            Marker(
              point: geom.centroid,
              width: 170,
              height: 52,
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Align(alignment: Alignment.centerLeft, child: _areaChip(geom)),
              ),
            ),
          ]),
        ],
        if (_gps != null && !_isDrawing) ...[
          if (_showNearYouCard)
            CircleLayer(
              circles: [
                for (final opt in kRadiusOptions)
                  CircleMarker(
                    point: _gps!,
                    radius: opt.meters,
                    useRadiusInMeter: true,
                    color: (opt.meters - _selectedRadius).abs() < 1
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                        : const Color(0xFF2563EB).withValues(alpha: 0.04),
                    borderColor: (opt.meters - _selectedRadius).abs() < 1
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF2563EB).withValues(alpha: 0.55),
                    borderStrokeWidth:
                        (opt.meters - _selectedRadius).abs() < 1 ? 2.5 : 1.25,
                  ),
              ],
            ),
          if (_showNearYouCard &&
              _radiusBuildings != null &&
              _radiusBuildings!.features.isNotEmpty) ...[
            if (_selectedRadius <= 2000)
              PolygonLayer(
                polygons: [
                  for (final b in _radiusBuildings!.features)
                    Polygon(
                      points: b.outerRing,
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.55),
                      borderColor: const Color(0xFF0F766E),
                      borderStrokeWidth: 1.0,
                    ),
                ],
              )
            else ...[
              PolygonLayer(
                polygons: [
                  for (final b in _radiusBuildings!.features.take(500))
                    Polygon(
                      points: b.outerRing,
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.45),
                      borderColor: const Color(0xFF0F766E),
                      borderStrokeWidth: 0.8,
                    ),
                ],
              ),
              if (_radiusBuildings!.features.length > 500)
                CircleLayer(
                  circles: [
                    for (final b in _radiusBuildings!.features.skip(500))
                      CircleMarker(
                        point: b.centroid,
                        radius: 3,
                        useRadiusInMeter: false,
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.70),
                        borderColor: const Color(0xFF0F766E),
                        borderStrokeWidth: 0.5,
                      ),
                  ],
                ),
            ],
          ],
        ],
        // Home dashboard uses a fixed screen-centre gauge over GPS; pulse only
        // while locating / non-home modes.
        if (_gps != null && !_homeDashboard)
          MarkerLayer(markers: [
            Marker(
              point: _gps!,
              width: 76,
              height: 76,
              child: Tooltip(
                message: 'Your GPS location',
                child: _GpsPulse(
                  color: _locAqi?.aqi != null
                      ? aqiCategory(_locAqi!.aqi!).color
                      : const Color(0xFF3B82F6),
                ),
              ),
            ),
          ]),
        if (_draft.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points: [..._draft, if (_draft.length > 2) _draft.first],
              color: AppColors.cyan,
              strokeWidth: 2.5,
            ),
          ]),
        if (_draft.isNotEmpty)
          MarkerLayer(markers: [
            for (final p in _draft) Marker(point: p, width: 14, height: 14, child: _vertexDot()),
          ]),
        if (_plumes.isNotEmpty && _showPlumes)
          MarkerLayer(markers: [
            for (final p in _plumes)
              Marker(
                point: p.point,
                width: 24,
                height: 24,
                child: GestureDetector(
                  onTap: () => _showPlume(p),
                  child: Center(
                    child: Container(
                      width: (p.confidence == 'high' ? 9 : 7) * 2.0,
                      height: (p.confidence == 'high' ? 9 : 7) * 2.0,
                      decoration: BoxDecoration(
                        color: (p.confidence == 'high'
                                ? const Color(0xFFFB9B06)
                                : const Color(0xFF781C6D))
                            .withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
      ],
      ),
    );
  }

  /// Ring vertices without the closing duplicate of the first point.
  List<LatLng> _distinctRing(List<LatLng> ring) =>
      ring.length > 1 && ring.first == ring.last ? ring.sublist(0, ring.length - 1) : ring;

  Widget _vertexDot() => Container(
        decoration: BoxDecoration(
          color: AppColors.softMint,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.mint, width: 3),
          boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.7), blurRadius: 8)],
        ),
      );

  Widget _areaChip(AreaGeometry geom) => GlassPanel(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selected Area',
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            Text(_formatArea(geom.areaKm2),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  String _formatArea(double km2) {
    if (km2 >= 100) return '${km2.toStringAsFixed(0)} km²';
    if (km2 >= 0.01) return '${km2.toStringAsFixed(2)} km²';
    return '${(km2 * 1e6).toStringAsFixed(0)} m²';
  }

  void _fitArea() {
    final geom = _geometry;
    if (geom == null) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(geom.ring),
      padding: const EdgeInsets.all(48),
    ));
  }

  // ---------- Floating header ----------

  Widget _header({required bool wide, required bool compact}) {
    final brand = GlassPanel(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 10),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: BrandLogo(
          size: compact ? 20 : 24,
          tagline: compact ? null : 'See Today. A Healthier Tomorrow.',
        ),
      ),
    );
    final modeBar = WeatherModeBar(
      mode: _weatherMode,
      onModeChanged: (m) => setState(() {
        _weatherMode = m;
        if (m == WeatherOverlayMode.none) {
          _readoutTappedCoordinate = null;
          _readoutHoverCoordinate = null;
          _readoutHoverPosition = null;
        }
      }),
      is3d: _is3dMode,
      onToggle3d: _toggle3dMode,
      isSatellite: _satellite,
      onToggleMap: _toggleSatellite,
      compact: compact,
    );
    final account = GlassIconButton(
      icon: Icons.person_outline,
      tooltip: 'Account',
      size: compact ? 38 : 44,
      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
    );
    if (wide) {
      return Row(children: [
        brand,
        const Spacer(),
        modeBar,
        const SizedBox(width: 10),
        account,
      ]);
    }
    return Row(children: [
      GlassIconButton(
        icon: Icons.menu,
        tooltip: 'Menu & Tools',
        size: 36,
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      const SizedBox(width: 5),
      Flexible(
        child: GlassPanel(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: BrandLogo(size: 13.5),
          ),
        ),
      ),
      const SizedBox(width: 4),
      modeBar,
      const SizedBox(width: 5),
      GlassIconButton(
        icon: Icons.person_outline,
        tooltip: 'Account',
        size: 36,
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    ]);
  }

  Widget _searchField({bool compact = false}) => CompositedTransformTarget(
        link: _searchLink,
        child: GlassPanel(
          radius: 22,
          padding: EdgeInsets.only(left: compact ? 10 : 14, right: 4),
          child: SizedBox(
            height: compact ? 38 : 40,
            child: Row(children: [
              _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
                    )
                  : Icon(Icons.search, size: compact ? 17 : 19, color: AppColors.textSecondary),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _searchPlaces,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: compact ? 12.5 : 13.5, color: AppColors.cloudWhite),
                  cursorColor: AppColors.mint,
                  decoration: InputDecoration(
                    hintText: compact ? 'Search…' : 'Search places',
                    hintStyle: TextStyle(fontSize: compact ? 12.5 : 13.5, color: AppColors.textSecondary),
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (_searchCtl.text.isNotEmpty || _searchResults != null)
                IconButton(
                  tooltip: 'Clear search',
                  constraints: BoxConstraints.tightFor(width: compact ? 30 : 34, height: compact ? 30 : 34),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.close, size: compact ? 15 : 17, color: AppColors.textSecondary),
                  onPressed: _clearSearch,
                ),
            ]),
          ),
        ),
      );

  Widget _searchResultsView(double width) {
    final results = _searchResults!;
    return SizedBox(
      width: width,
      child: GlassPanel(
        radius: 16,
        opacity: 0.86,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          type: MaterialType.transparency,
          child: results.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('No places found',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                )
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final p in results)
                    InkWell(
                      onTap: () => _goToPlace(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(children: [
                          const Icon(Icons.place_outlined, size: 18, color: AppColors.mint),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              if (p.region.isNotEmpty)
                                Text(p.region,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11.5, color: AppColors.textSecondary)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }

  /// Live AQI at the device location. Only real fixes and real /aqi values are
  /// shown; every other state says plainly what is missing.
  /// Live AQI at the device location. Only real fixes and real /aqi values are
  /// shown; every other state says plainly what is missing.
  // Kept for analysis / Near You flows; Design 5 uses [HomeAqiDashboard] instead.
  // ignore: unused_element
  Widget _locationCard({required double maxWidth, bool compact = false}) {
    final record = _locAqi;
    final value = record?.aqi;
    final cat = value != null ? aqiCategory(value) : null;

    Widget badge({double size = 46}) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (cat?.color ?? AppColors.slateBlue).withValues(alpha: cat == null ? 0.6 : 1),
            boxShadow: cat == null
                ? null
                : [BoxShadow(color: cat.color.withValues(alpha: 0.55), blurRadius: 14)],
          ),
          child: _gps != null && _locAqiLoading
              ? SizedBox(
                  width: size * 0.45,
                  height: size * 0.45,
                  child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                )
              : value != null
                  ? FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(value.round().toString(),
                            style: TextStyle(
                                fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    )
                  : Icon(
                      _gps == null && _openLocationFailed
                          ? Icons.location_off_outlined
                          : (_gps == null ? Icons.my_location : Icons.cloud_off_outlined),
                      size: size * 0.42,
                      color: AppColors.cloudWhite),
        );

    if (!_locCardOpen) {
      return Semantics(
        button: true,
        label: 'Show location AQI',
        child: GestureDetector(
          onTap: () => setState(() => _locCardOpen = true),
          child: GlassPanel(
            radius: 20,
            opacity: 0.88,
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              badge(size: compact ? 32 : 36),
              const SizedBox(width: 8),
              Text(cat?.label ?? 'My AQI',
                  style: TextStyle(fontSize: compact ? 12 : 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_up, size: 16, color: AppColors.textSecondary),
            ]),
          ),
        ),
      );
    }

    final String title;
    final String subtitle;
    VoidCallback? retry;
    if (_gps == null) {
      if (_openLocationFailed) {
        title = 'Location unavailable';
        subtitle = 'Allow location access to see AQI where you are.';
        retry = () => _locateOnOpen(recenter: true);
      } else {
        title = 'Finding your location…';
        subtitle = 'Waiting for GPS';
      }
    } else if (_locAqiLoading) {
      title = 'Loading AQI…';
      subtitle = _locPlace ?? 'Your location';
    } else if (_locAqiError != null) {
      title = 'AQI unavailable';
      subtitle = 'Could not reach the AQI service.';
      retry = () => _loadLocationAqi(_gps!);
    } else if (cat == null) {
      title = 'No AQI data';
      subtitle = 'No reading returned for this location.';
      retry = () => _loadLocationAqi(_gps!);
    } else {
      title = cat.label;
      subtitle = 'Live AQI · ${_locPlace ?? 'Your location'}';
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: GlassPanel(
        radius: 18,
        opacity: 0.90,
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          badge(size: compact ? 38 : 46),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MY LOCATION',
                    style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary.withValues(alpha: 0.9))),
                const SizedBox(height: 2),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: compact ? 13.5 : 15,
                        fontWeight: FontWeight.w800,
                        color: cat?.color ?? AppColors.cloudWhite)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (retry != null)
            IconButton(
              tooltip: 'Retry',
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              icon: const Icon(Icons.refresh, size: 18, color: AppColors.mint),
              onPressed: retry,
            ),
          if (_gps != null)
            IconButton(
              tooltip: 'Centre on my location',
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              icon: const Icon(Icons.my_location, size: 18, color: AppColors.mint),
              onPressed: _recenter,
            ),
          IconButton(
            tooltip: 'Minimise',
            constraints: const BoxConstraints.tightFor(width: 32, height: 34),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
            onPressed: () => setState(() => _locCardOpen = false),
          ),
        ]),
      ),
    );
  }

  Widget _coordsChip({bool compact = false}) {
    return GlassPanel(
      radius: 16,
      opacity: 0.88,
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 5 : 7,
        compact ? 10 : 14,
        compact ? 5 : 7,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: compact ? 24 : 28,
            height: compact ? 24 : 28,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.place_outlined, size: compact ? 13 : 15, color: AppColors.mint),
          ),
          SizedBox(width: compact ? 6 : 8),
          ValueListenableBuilder<LatLng>(
            valueListenable: _center,
            builder: (_, c, _) => Text(
              'Lat: ${c.latitude.toStringAsFixed(5)}° | '
              'Long: ${c.longitude.toStringAsFixed(5)}°',
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------- Navigation drawer ----------

  Widget _navDrawer() => Drawer(
        width: 300,
        backgroundColor: AppColors.deepForest.withValues(alpha: 0.96),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: BrandLogo(size: 22)),
                IconButton(
                  tooltip: 'Close menu',
                  icon: const Icon(Icons.close, color: AppColors.softMint),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: 12),
              Divider(color: AppColors.border),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _drawerItem(Icons.map_outlined, 'Map View', selected: true,
                        onTap: () => Navigator.of(context).pop()),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Text(
                        'TOOLS & ANALYSIS',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    _drawerItem(Icons.pentagon_outlined, 'Draw Area', onTap: () {
                      Navigator.of(context).pop();
                      _startDrawing();
                    }),
                    _drawerItem(Icons.upload_file_outlined, 'Upload KML / KMZ', onTap: () {
                      Navigator.of(context).pop();
                      _uploadKml();
                    }),
                    _drawerItem(
                      Icons.radar_outlined,
                      'Near You Radius Analysis',
                      selected: _showNearYouCard && _gps != null,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (_showNearYouCard) {
                          setState(() => _showNearYouCard = false);
                        } else {
                          _onSelectRadius(_selectedRadius);
                        }
                      },
                    ),
                    _drawerItem(
                      Icons.analytics_outlined,
                      'Analysis & Reports',
                      selected: _sheet != _SheetSize.collapsed,
                      onTap: () {
                        Navigator.of(context).pop();
                        setState(() => _sheet =
                            _sheet == _SheetSize.collapsed ? _SheetSize.half : _SheetSize.collapsed);
                      },
                    ),
                    if (_geometry != null) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Text(
                          'ACTIVE AREA (${_formatArea(_geometry!.areaKm2)})',
                          style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.mint,
                          ),
                        ),
                      ),
                      _drawerItem(Icons.center_focus_strong_outlined, 'Zoom to Area', onTap: () {
                        Navigator.of(context).pop();
                        _fitArea();
                      }),
                      if (_drawnByUser)
                        _drawerItem(Icons.download_outlined, 'Download KML', onTap: () {
                          Navigator.of(context).pop();
                          if (!_savingKml) _downloadKml();
                        }),
                      _drawerItem(Icons.delete_outline, 'Clear Area', onTap: () {
                        Navigator.of(context).pop();
                        _clear();
                      }),
                    ],
                  ],
                ),
              ),
              Divider(color: AppColors.border),
              _drawerItem(Icons.logout, 'Logout', onTap: () {
                Navigator.of(context).pop();
                _logout();
              }),
            ]),
          ),
        ),
      );

  Widget _drawerItem(IconData icon, String label,
          {bool selected = false, required VoidCallback onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected ? AppColors.mint.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            onTap: onTap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Icon(icon, color: selected ? AppColors.mint : AppColors.softMint),
            title: Text(label,
                style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.cloudWhite)),
          ),
        ),
      );

  // ---------- Left tool rail & right controls ----------

  Widget _toolRail() => GlassPanel(
        radius: 26,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: _railW,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _railBtn(Icons.pentagon_outlined, 'Draw polygon', _startDrawing),
            _railBtn(Icons.upload_file_outlined, 'Upload KML/KMZ', _uploadKml),
            _railBtn(Icons.center_focus_strong_outlined, 'Zoom to area',
                _geometry == null ? null : _fitArea),
            if (_geometry != null && _drawnByUser)
              _railBtn(Icons.download_outlined, 'Download KML as file',
                  _savingKml ? null : _downloadKml),
            _railBtn(Icons.delete_outline, 'Clear area', _geometry == null ? null : _clear),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Divider(height: 8, color: AppColors.border),
            ),
            _railBtn(Icons.radar_outlined, 'Near you radius analysis', _gps == null ? null : () {
              if (_showNearYouCard) {
                setState(() => _showNearYouCard = false);
              } else {
                _onSelectRadius(_selectedRadius);
              }
            }, active: _showNearYouCard && _gps != null),
            _railBtn(Icons.analytics_outlined, 'Analysis workspace', () {
              setState(() => _sheet =
                  _sheet == _SheetSize.collapsed ? _SheetSize.half : _SheetSize.collapsed);
            }, active: _sheet != _SheetSize.collapsed),
          ]),
        ),
      );

  Widget _railBtn(IconData icon, String tooltip, VoidCallback? onTap, {bool active = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          style: active
              ? IconButton.styleFrom(backgroundColor: AppColors.mint.withValues(alpha: 0.28))
              : null,
          icon: Icon(icon,
              size: 21,
              color: onTap == null
                  ? AppColors.textMuted.withValues(alpha: 0.35)
                  : (active ? AppColors.white : AppColors.softMint)),
        ),
      );

  Widget _gpsChip() {
    final (status, color) = _openLocating
        ? ('Locating…', AppColors.softMint)
        : _gps != null
            ? ('Location found', AppColors.mint)
            : _openLocationFailed
                ? ('Location unavailable', const Color(0xFFFBBF24))
                : ('Not located', AppColors.textMuted);
    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.mint.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.mint.withValues(alpha: 0.5)),
          ),
          child: const Icon(Icons.gps_fixed, size: 16, color: AppColors.mint),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GPS', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(status, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ]),
        ]),
      ]),
    );
  }

  /// The AQI category scale used by the gauges (not measured data).
  static const _aqiBands = <(double, String)>[
    (25, '0–50'),
    (75, '51–100'),
    (125, '101–150'),
    (175, '151–200'),
    (250, '201–300'),
    (350, '301+'),
  ];

  Widget _aqiLegend() => GlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
        child: SizedBox(
          width: 176,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('AQI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              InkWell(
                onTap: () => setState(() => _aqiLegendOpen = false),
                child: const Icon(Icons.keyboard_arrow_up, size: 18, color: AppColors.textMuted),
              ),
            ]),
            const SizedBox(height: 8),
            for (final (sample, range) in _aqiBands)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: aqiCategory(sample).color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(aqiCategory(sample).label,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Text(range, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ),
          ]),
        ),
      );

  PopupMenuItem<String> _layerItem(String value, String label, IconData icon, bool active) =>
      PopupMenuItem(
        value: value,
        height: 44,
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.mint.withValues(alpha: 0.2) : AppColors.slateBlue,
              border: Border.all(color: active ? AppColors.mint : AppColors.border),
            ),
            child: Icon(icon, size: 16, color: active ? AppColors.mint : AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.cloudWhite : AppColors.textSecondary)),
        ]),
      );

  /// [legendFits] is false when the open sheet would cover the AQI legend.
  Widget _mapControls({required bool wide, required bool legendFits}) {
    final tiles = _methaneTiles;
    final aqiLegendOpen = legendFits && (_aqiLegendOpen ?? wide);
    // ~12% smaller than prior 44/40 — still ≥36 for comfortable taps.
    final btnSize = wide ? 38.0 : 34.0;
    final iconSize = wide ? 18.0 : 16.5;
    const gap = 8.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      GlassPanel(
        radius: btnSize / 2,
        child: PopupMenuButton<String>(
          tooltip: 'Map layers',
          color: AppColors.deepBlue,
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          onSelected: (v) {
            switch (v) {
              case 'satellite':
                _setSatellite(true);
              case 'map':
                _setSatellite(false);
              case 'methane':
                setState(() => _showMethaneOverlay = !_showMethaneOverlay);
              case 'plumes':
                setState(() => _showPlumes = !_showPlumes);
            }
          },
          itemBuilder: (_) => [
            _layerItem('map', 'Light map (OSM)', Icons.map_outlined, !_satellite),
            _layerItem('satellite', 'Satellite', Icons.satellite_alt_outlined, _satellite),
            if (tiles?.tileUrl != null) ...[
              const PopupMenuDivider(),
              _layerItem('methane', 'Methane overlay', Icons.blur_on, _showMethaneOverlay),
            ],
            if (_plumes.isNotEmpty)
              _layerItem('plumes', 'Methane plumes', Icons.scatter_plot_outlined, _showPlumes),
          ],
          child: SizedBox(
            width: btnSize,
            height: btnSize,
            child: Icon(Icons.layers_outlined, size: iconSize, color: AppColors.softMint),
          ),
        ),
      ),
      const SizedBox(height: gap),
      GlassIconButton(
        icon: Icons.navigation_outlined,
        tooltip: _gps != null ? 'Centre on my GPS location' : 'Find my location',
        size: btnSize,
        onPressed: _openLocating ? null : _recenter,
      ),
      const SizedBox(height: gap),
      GlassPanel(
        radius: btnSize / 2,
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Zoom in',
              constraints: BoxConstraints.tightFor(width: btnSize, height: btnSize),
              icon: Icon(Icons.add, size: iconSize, color: AppColors.softMint),
              onPressed: () {
                final c = _map.camera;
                final center = _homeDashboard && _gps != null ? _gps! : c.center;
                _map.move(center, c.zoom + 1);
              },
            ),
            Container(width: btnSize * 0.5, height: 1, color: AppColors.border),
            IconButton(
              tooltip: 'Zoom out',
              constraints: BoxConstraints.tightFor(width: btnSize, height: btnSize),
              icon: Icon(Icons.remove, size: iconSize, color: AppColors.softMint),
              onPressed: () {
                final c = _map.camera;
                final center = _homeDashboard && _gps != null ? _gps! : c.center;
                _map.move(center, c.zoom - 1);
              },
            ),
          ]),
        ),
      ),
      if (tiles != null) ...[
        const SizedBox(height: gap),
        _legendOpen
            ? _legend(tiles.legend)
            : GlassIconButton(
                icon: Icons.legend_toggle,
                tooltip: 'Show methane legend',
                size: btnSize,
                onPressed: () => setState(() => _legendOpen = true),
              ),
      ],
      const SizedBox(height: gap),
      aqiLegendOpen
          ? _aqiLegend()
          : GlassIconButton(
              icon: Icons.info_outline,
              tooltip: 'Show AQI legend',
              size: btnSize,
              onPressed: () => setState(() {
                _aqiLegendOpen = true;
                if (!legendFits) _sheet = _SheetSize.collapsed;
              }),
            ),
    ]);
  }

  Widget _legend(MethaneLegend legend, {bool floating = true}) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(legend.title ?? 'Methane',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          if (floating)
            InkWell(
              onTap: () => setState(() => _legendOpen = false),
              child: const Icon(Icons.close, size: 15, color: AppColors.textMuted),
            ),
        ]),
        const SizedBox(height: 8),
        if (legend.palette.length >= 2)
          Container(
            height: 10,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: legend.palette),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        const SizedBox(height: 4),
        Row(children: [
          Text(legend.min?.toStringAsFixed(0) ?? '', style: const TextStyle(fontSize: 11)),
          const Spacer(),
          Text('${legend.max?.toStringAsFixed(0) ?? ''} ${legend.unit ?? ''}',
              style: const TextStyle(fontSize: 11)),
        ]),
        if (_methaneNote != null) ...[
          const SizedBox(height: 6),
          Text(_methaneNote!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ],
    );
    if (!floating) return body;
    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.all(12),
      child: SizedBox(width: 176, child: body),
    );
  }

  // ---------- Bottom analysis sheet ----------

  double _snapHeight(_SheetSize s, double maxH, {double collapsedH = _collapsedH}) => switch (s) {
        _SheetSize.collapsed => collapsedH,
        _SheetSize.half => math.min(maxH, math.max(300.0, maxH * 0.55)),
        _SheetSize.full => maxH,
      };

  void _onSheetDragEnd(DragEndDetails d, double maxH, {double collapsedH = _collapsedH}) {
    final h = _dragHeight ?? _snapHeight(_sheet, maxH, collapsedH: collapsedH);
    final v = d.primaryVelocity ?? 0;
    final order = _SheetSize.values;
    _SheetSize next;
    if (v < -500) {
      next = order[math.min(order.length - 1, _sheet.index + 1)];
    } else if (v > 500) {
      next = order[math.max(0, _sheet.index - 1)];
    } else {
      next = order.reduce((a, b) =>
          (_snapHeight(a, maxH, collapsedH: collapsedH) - h).abs() <=
                  (_snapHeight(b, maxH, collapsedH: collapsedH) - h).abs()
              ? a
              : b);
    }
    setState(() {
      _sheet = next;
      _dragHeight = null;
    });
  }

  double _sheetWidth(BoxConstraints c, bool wide) =>
      wide ? math.min(920.0, c.maxWidth - 2 * (_railW + 36)) : math.min(500.0, c.maxWidth - 24);

  /// [hidden] keeps the sheet (and any loaded analysis) mounted while drawing.
  Widget _sheetView(BoxConstraints c, bool wide, MediaQueryData mq, {required bool hidden}) {
    final collapsedH = wide ? _collapsedH : 46.0;
    final maxH = math.max(collapsedH + 160, c.maxHeight - mq.padding.top - (wide ? 96 : 80));
    final height = _dragHeight ?? _snapHeight(_sheet, maxH, collapsedH: collapsedH);
    final width = _sheetWidth(c, wide);
    return Positioned(
      left: 0,
      right: 0,
      bottom: mq.padding.bottom + 8,
      child: Offstage(
        offstage: hidden,
        child: Center(
        child: AnimatedContainer(
          duration: _dragHeight == null ? const Duration(milliseconds: 260) : Duration.zero,
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          child: GlassPanel(
            radius: 24,
            opacity: 0.74,
            blur: 18,
            child: LayoutBuilder(builder: (context, bc) {
              final collapsed = bc.maxHeight < 150;
              return Column(children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) => setState(() {
                    final h = _dragHeight ?? _snapHeight(_sheet, maxH, collapsedH: collapsedH);
                    _dragHeight = (h - d.delta.dy).clamp(collapsedH, maxH);
                  }),
                  onVerticalDragEnd: (d) => _onSheetDragEnd(d, maxH, collapsedH: collapsedH),
                  onTap: collapsed ? () => setState(() => _sheet = _SheetSize.half) : null,
                  child: collapsed ? _collapsedBar(compact: !wide) : _sheetHeader(),
                ),
                Expanded(child: _sheetBody(wide: width >= 700)),
              ]);
            }),
          ),
        ),
        ),
      ),
    );
  }

  Widget _handle() => Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.softMint.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _collapsedBar({bool compact = false}) {
    final geom = _geometry;
    return SizedBox(
      height: compact ? 44 : _collapsedH - 4,
      child: Column(children: [
        SizedBox(height: compact ? 4 : 6),
        _handle(),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
            child: Row(children: [
              Icon(Icons.tune, size: compact ? 16 : 18, color: AppColors.mint),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Text(
                  geom == null
                      ? (compact ? 'Area tools & analysis' : 'Area tools & analysis · draw or upload an area')
                      : 'Area tools · ${_formatArea(geom.areaKm2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12.5 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cloudWhite,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Expand panel',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: compact ? 32 : 40,
                  height: compact ? 32 : 40,
                ),
                icon: Icon(
                  Icons.keyboard_arrow_up,
                  size: compact ? 20 : 24,
                  color: AppColors.softMint,
                ),
                onPressed: () => setState(() => _sheet = _SheetSize.half),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  static const _tabMeta = {
    _SheetTab.area: ('Area', Icons.pentagon_outlined),
    _SheetTab.airQuality: ('Air Quality', Icons.air),
    _SheetTab.weather: ('Weather', Icons.cloud_outlined),
    _SheetTab.methane: ('Methane', Icons.local_fire_department_outlined),
    _SheetTab.results: ('Results', Icons.insights_outlined),
  };

  Widget _sheetHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
        child: Column(children: [
          _handle(),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 560;
                final tabs = GlassSegmented<_SheetTab>(
                  values: _SheetTab.values,
                  selected: _tab,
                  dense: !wide,
                  expand: wide,
                  label: (t) => _tabMeta[t]!.$1,
                  icon: (t) => _tabMeta[t]!.$2,
                  onChanged: (t) => setState(() => _tab = t),
                );
                return wide
                    ? tabs
                    : SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs);
              }),
            ),
            IconButton(
              tooltip: _sheet == _SheetSize.full ? 'Shrink panel' : 'Expand panel',
              icon: Icon(
                  _sheet == _SheetSize.full ? Icons.unfold_less : Icons.unfold_more,
                  color: AppColors.softMint),
              onPressed: () => setState(() => _sheet =
                  _sheet == _SheetSize.full ? _SheetSize.half : _SheetSize.full),
            ),
            IconButton(
              tooltip: 'Close panel',
              icon: const Icon(Icons.close, color: AppColors.softMint),
              onPressed: () => setState(() => _sheet = _SheetSize.collapsed),
            ),
          ]),
        ]),
      );

  Widget _sheetBody({required bool wide}) {
    final args = _analysis;
    final showPanel = args != null && _tab != _SheetTab.methane;
    final area = _tab == _SheetTab.area;
    final section = switch (_tab) {
      _SheetTab.area => AnalysisSection.overview,
      _SheetTab.airQuality => AnalysisSection.airQuality,
      _SheetTab.weather => AnalysisSection.weather,
      _ => AnalysisSection.all,
    };
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        if (args != null)
          Offstage(
            offstage: !showPanel,
            child: TickerMode(
              enabled: showPanel,
              child: AnalysisPanel(
                key: ValueKey(_analysisRun),
                args: args,
                section: section,
                leading: area ? _areaWidgets(wide) : const [],
                trailing: area ? [const SizedBox(height: 12), _methaneOverview()] : const [],
                onOpenSection: (s) => setState(() => _tab = switch (s) {
                      AnalysisSection.airQuality => _SheetTab.airQuality,
                      AnalysisSection.weather => _SheetTab.weather,
                      _ => _SheetTab.results,
                    }),
              ),
            ),
          ),
        if (area && args == null)
          _areaTab(wide)
        else if (_tab == _SheetTab.methane)
          _methaneTab(wide)
        else if (args == null)
          _noAnalysisYet(),
      ]),
    );
  }

  // ---------- Area tab ----------

  List<Widget> _areaWidgets(bool wide) {
    final tools = GlassSection(
      title: 'Area Selection',
      icon: Icons.pentagon_outlined,
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        _toolTile(Icons.draw_outlined, 'Draw Polygon', _startDrawing),
        _toolTile(Icons.cloud_upload_outlined, 'Upload KML/KMZ', _uploadKml),
        _toolTile(Icons.delete_outline, 'Clear Area', _clear),
        if (_geometry != null && _drawnByUser)
          _toolTile(Icons.download_outlined, 'Download KML', _savingKml ? null : _downloadKml),
      ]),
    );
    final selected = _selectedAreaCard();
    final dates = GlassSection(
      title: 'Date Range',
      icon: Icons.date_range_outlined,
      child: Row(children: [
        Expanded(child: _dateField('Start date', _startDate, true)),
        const SizedBox(width: 10),
        Expanded(child: _dateField('End date', _endDate, false)),
      ]),
    );
    final run = GlassSection(
      title: 'Analysis Type',
      icon: Icons.science_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: GlassSegmented<_AnalysisType>(
            values: _AnalysisType.values,
            selected: _analysisType,
            dense: true,
            label: (t) => switch (t) {
              _AnalysisType.aqi => 'AQI & Pollutants',
              _AnalysisType.weather => 'Weather',
              _AnalysisType.methane => 'Methane',
            },
            icon: (t) => switch (t) {
              _AnalysisType.aqi => Icons.air,
              _AnalysisType.weather => Icons.cloud_outlined,
              _AnalysisType.methane => Icons.local_fire_department_outlined,
            },
            onChanged: (t) => setState(() => _analysisType = t),
          ),
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: 'Run Analysis',
          height: 46,
          icon: Icons.play_arrow_rounded,
          busy: _analysisType == _AnalysisType.methane && _methaneLoading,
          onPressed: _geometry == null
              ? null
              : _analysisType == _AnalysisType.methane
                  ? (_methaneLoading
                      ? null
                      : () {
                          setState(() => _tab = _SheetTab.methane);
                          _analyseMethane();
                        })
                  : _analyse,
        ),
      ]),
    );
    if (!wide) {
      return [
        tools,
        const SizedBox(height: 12),
        selected,
        const SizedBox(height: 12),
        dates,
        const SizedBox(height: 12),
        run,
        const SizedBox(height: 12),
      ];
    }
    return [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 3, child: tools),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: selected),
        ]),
      ),
      const SizedBox(height: 12),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 2, child: dates),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: run),
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Area tab before any Run Analysis: tools plus empty result cards.
  Widget _areaTab(bool wide) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ..._areaWidgets(wide),
          const OverviewCard(
            title: 'AQI & Pollutant Analysis',
            icon: Icons.eco_outlined,
            child: Text('Select an area and press Run Analysis to load air quality.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 12),
          const OverviewCard(
            title: 'Weather',
            icon: Icons.cloud_outlined,
            child: Text('Weather for the selected area appears after Run Analysis.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 12),
          _methaneOverview(),
        ]),
      );

  /// Methane summary for the Area tab, from the current methane results.
  Widget _methaneOverview() {
    final tiles = _methaneTiles;
    double? peak;
    for (final p in _plumes) {
      final e = p.enhancement;
      if (e != null && (peak == null || e > peak)) peak = e;
    }
    return OverviewCard(
      title: 'Methane Analysis',
      icon: Icons.bubble_chart_outlined,
      status: tiles != null ? 'Layer on map' : null,
      child: LayoutBuilder(builder: (context, c) {
        final toggles = _methaneToggles();
        final Widget info = tiles == null
            ? Text(
                _methaneLoading
                    ? 'Analysing methane…'
                    : 'Choose Methane in Analysis Type, or open the Methane tab, to load plumes.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))
            : Row(children: [
                Expanded(child: MetricText(label: 'Plumes', value: '${_plumes.length}')),
                Expanded(
                  child: MetricText(
                    label: 'Peak enhancement',
                    value: peak == null ? '—' : '${peak.toStringAsFixed(1)} ppm·m',
                  ),
                ),
              ]);
        final view = OutlinedButton(
          onPressed: tiles == null
              ? () => setState(() => _tab = _SheetTab.methane)
              : () {
                  setState(() {
                    _showMethaneOverlay = true;
                    _sheet = _SheetSize.collapsed;
                  });
                  _fitArea();
                },
          child: Text(tiles == null ? 'Open Methane' : 'View Layer'),
        );
        if (c.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (tiles != null) ...[toggles, const SizedBox(height: 12)],
            info,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: view),
          ]);
        }
        return Row(children: [
          if (tiles != null) ...[toggles, const SizedBox(width: 16)],
          Expanded(child: info),
          const SizedBox(width: 12),
          view,
        ]);
      }),
    );
  }

  /// Overlay / Plumes / Legend visibility toggles for the methane results.
  Widget _methaneToggles() {
    Widget pill(String label, bool on, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.mint : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? AppColors.white : AppColors.softMint)),
          ),
        );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          pill('Overlay', _showMethaneOverlay,
              () => setState(() => _showMethaneOverlay = !_showMethaneOverlay)),
          pill('Plumes', _showPlumes, () => setState(() => _showPlumes = !_showPlumes)),
          pill('Legend', _legendOpen, () => setState(() => _legendOpen = !_legendOpen)),
        ]),
      ),
    );
  }

  Widget _toolTile(IconData icon, String label, VoidCallback? onTap) => SizedBox(
        width: 124,
        child: Material(
          color: AppColors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(children: [
                Icon(icon, size: 22, color: onTap == null ? AppColors.textMuted : AppColors.mint),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );

  Widget _selectedAreaCard() {
    final geom = _geometry;
    return GlassSection(
      title: 'Selected Area',
      icon: Icons.crop_square,
      child: geom == null
          ? const Text('No area selected',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _stat('Area', _formatArea(geom.areaKm2))),
                Expanded(child: _stat('Vertices', '${geom.vertexCount}')),
              ]),
              const SizedBox(height: 10),
              Text(
                '${_kmlName ?? 'Drawn area'} · centre '
                '${geom.centroid.latitude.toStringAsFixed(4)}, '
                '${geom.centroid.longitude.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.check_circle, size: 14, color: AppColors.mint),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Ready to analyse',
                      style: TextStyle(fontSize: 12, color: AppColors.mint)),
                ),
                TextButton.icon(
                  onPressed: _fitArea,
                  icon: const Icon(Icons.center_focus_strong_outlined, size: 16),
                  label: const Text('Zoom to Area'),
                ),
              ]),
            ]),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _noAnalysisYet() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insights_outlined, size: 36, color: AppColors.mint),
            const SizedBox(height: 10),
            const Text('No analysis yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Select an area in the Area tab, choose a date range and press Run Analysis.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _tab = _SheetTab.area),
              child: const Text('Go to Area'),
            ),
          ]),
        ),
      );

  // ---------- Methane tab ----------

  Widget _methaneTab(bool wide) {
    final tiles = _methaneTiles;
    String f(double? v, [int d = 1]) => v == null ? '—' : v.toStringAsFixed(d);
    final run = GlassSection(
      title: 'Methane Analysis',
      icon: Icons.local_fire_department_outlined,
      trailing: tiles != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Layer on map',
                  style: TextStyle(fontSize: 11, color: AppColors.mint)),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Methane plumes and the concentration layer for the selected area, '
          '${ymd(_startDate)} to ${ymd(_endDate)}.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: 'Analyse Methane',
          height: 44,
          icon: Icons.local_fire_department_outlined,
          busy: _methaneLoading,
          onPressed: _geometry == null || _methaneLoading ? null : _analyseMethane,
        ),
        if (_geometry == null) ...[
          const SizedBox(height: 8),
          const Text('Draw or upload an area first.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ]),
    );
    final legend = tiles == null
        ? null
        : GlassSection(
            title: 'Legend',
            icon: Icons.legend_toggle,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('On map', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              Switch(
                value: _legendOpen,
                onChanged: (v) => setState(() => _legendOpen = v),
              ),
            ]),
            child: _legend(tiles.legend, floating: false),
          );
    final plumes = GlassSection(
      title: 'Plumes',
      icon: Icons.blur_on,
      trailing: Text('${_plumes.length}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.mint)),
      child: _plumes.isEmpty
          ? Text(
              tiles == null ? 'Run the methane analysis to list plumes.' : 'No plumes found.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            )
          : Column(children: [
              for (final p in _plumes.take(50))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.circle,
                      size: 14,
                      color: p.confidence == 'high'
                          ? const Color(0xFFFB9B06)
                          : const Color(0xFF781C6D)),
                  title: Text('${f(p.enhancement)} ppm·m · ${p.confidence ?? '—'}'),
                  subtitle: Text(p.observedAt ?? '—',
                      style: const TextStyle(color: AppColors.textMuted)),
                  onTap: () {
                    _map.move(p.point, math.max(_map.camera.zoom, 12));
                    _showPlume(p);
                  },
                ),
              if (_plumes.length > 50)
                Text('Showing 50 of ${_plumes.length}; all are on the map.',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
    );
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      run,
      if (tiles != null) ...[const SizedBox(height: 12), _methaneToggles()],
      if (legend != null) ...[const SizedBox(height: 12), legend],
    ]);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: plumes),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              left,
              const SizedBox(height: 12),
              plumes,
            ]),
    );
  }

  // ---------- Drawing ----------

  Widget _drawingDock(BoxConstraints c, MediaQueryData mq) => Positioned(
        left: 8,
        right: 8,
        bottom: mq.padding.bottom + 8,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassPanel(
              radius: 22,
              opacity: 0.76,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [
                    Icon(Icons.draw_outlined, size: 20, color: AppColors.mint),
                    SizedBox(width: 10),
                    Text('Draw Area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  if (_locating) ...[
                    const SizedBox(height: 10),
                    _banner(
                      const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      'Getting your location…',
                    ),
                  ] else if (_locationNote != null) ...[
                    const SizedBox(height: 10),
                    _banner(const Icon(Icons.my_location, size: 18, color: AppColors.mint),
                        _locationNote!),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Tap the map to place vertices (${_draft.length} placed)',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                            onPressed: _cancelDrawing,
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8)),
                            child: const Text('Cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          onPressed:
                              _draft.isEmpty ? null : () => setState(() => _draft.removeLast()),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8)),
                          child: const Text('Undo'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GradientButton(
                        label: 'Finish',
                        height: 42,
                        onPressed: _draft.length >= 3 ? _finishDrawing : null,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _banner(Widget leading, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.mint.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.mint.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _dateField(String label, DateTime value, bool start) => InkWell(
        onTap: () => _pickDate(start),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today, size: 16, color: AppColors.mint),
            suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          child: Text(ymd(value), maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
        ),
      );
}

enum _SheetSize { collapsed, half, full }

enum _SheetTab { area, airQuality, weather, methane, results }

enum _AnalysisType { aqi, weather, methane }

/// Device-location marker: solid dot inside a soft halo and an expanding ring.
class _GpsPulse extends StatefulWidget {
  const _GpsPulse({required this.color});

  final Color color;

  @override
  State<_GpsPulse> createState() => _GpsPulseState();
}

class _GpsPulseState extends State<_GpsPulse> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return Stack(alignment: Alignment.center, children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_pulse.value);
          return Container(
            width: 22 + 54 * t,
            height: 22 + 54 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.7 * (1 - t)), width: 2),
            ),
          );
        },
      ),
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.22),
        ),
      ),
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 12),
            const BoxShadow(color: Colors.black45, blurRadius: 4),
          ],
        ),
      ),
    ]);
  }
}
