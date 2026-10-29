import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/json_utils.dart';
import '../models/period_logic.dart';
import '../models/weather.dart';
import '../services/api_client.dart';
import '../services/excel_export.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import '../widgets/common.dart';
import '../widgets/detail_widgets.dart';
import '../widgets/trend_chart.dart';
import 'analysis_screen.dart';

class DetailArgs {
  DetailArgs({
    required this.latitude,
    required this.longitude,
    required this.startDate,
    required this.maxDate,
    required this.date,
    required this.mode,
    this.placeName,
  });
  final double latitude, longitude;
  final DateTime startDate, maxDate, date;
  final ViewMode mode;
  final String? placeName;
}

/// Parameters and colours from AQIDetailPage.jsx.
const _params = <(String, String, Color)>[
  ('aqi', 'AQI', Color(0xFF14B8A6)),
  ('pm2_5', 'PM2.5 (µg/m³)', Color(0xFFEF4444)),
  ('pm10', 'PM10 (µg/m³)', Color(0xFFF59E0B)),
  ('co', 'CO (ppm)', Color(0xFF8B5CF6)),
  ('no2', 'NO₂ (µg/m³)', Color(0xFF3B82F6)),
  ('so2', 'SO₂ (µg/m³)', Color(0xFFEC4899)),
  ('o3', 'O₃ (µg/m³)', Color(0xFF10B981)),
  ('temperature', 'Temperature (°C)', Color(0xFFEF4444)),
  ('feels_like', 'Feels Like (°C)', Color(0xFFF97316)),
  ('humidity', 'Humidity (%)', Color(0xFF3B82F6)),
  ('wind_speed', 'Wind Speed (km/h)', Color(0xFF14B8A6)),
  ('wind_gusts', 'Wind Gusts (km/h)', Color(0xFF06B6D4)),
  ('uv_index', 'UV Index', Color(0xFFFBBF24)),
  ('precipitation', 'Precipitation (mm)', Color(0xFF60A5FA)),
  ('cloud_cover', 'Cloud Cover (%)', Color(0xFF9CA3AF)),
  ('visibility', 'Visibility (km)', Color(0xFFA855F7)),
  ('pressure', 'Pressure (mb)', Color(0xFF8B5CF6)),
];

const _weatherKeys = [
  'temperature', 'feels_like', 'humidity', 'wind_speed', 'wind_gusts', 'uv_index',
  'precipitation', 'cloud_cover', 'visibility', 'pressure',
];

/// One chart/table row: AQI fields and weather fields merged by time key.
class _Row {
  _Row(this.time, this.sortKey);
  final String time;
  DateTime sortKey;
  final Map<String, double?> values = {};
  String? trend;
  double? trendPercentage;
}

class AqiDetailScreen extends StatefulWidget {
  const AqiDetailScreen({super.key, required this.args});
  final DetailArgs args;

  @override
  State<AqiDetailScreen> createState() => _AqiDetailScreenState();
}

class _AqiDetailScreenState extends State<AqiDetailScreen> {
  final _api = ApiClient.instance;
  late ViewMode _mode = widget.args.mode;
  late DateTime _selectedDate = widget.args.date;
  final Set<String> _selected = {'aqi', 'pm2_5', 'pm10'};
  bool _multiple = true;
  bool _bar = false;

  bool _loading = false;
  String? _error;
  List<_Row> _rows = [];
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_token;
    final mode = _mode;
    setState(() {
      _loading = true;
      _error = null;
    });
    final a = widget.args;
    final lat = a.latitude, lng = a.longitude;
    final now = DateTime.now();
    final today = dateOnly(now);
    try {
      List<Map<String, dynamic>> aqi;
      List<Map<String, dynamic>> weather;
      List<Map<String, dynamic>> raws(List<HourlyWeather> l) => [for (final w in l) w.raw];
      switch (mode) {
        case ViewMode.live:
          final from = now.subtract(const Duration(hours: 1));
          final r = await Future.wait([
            _api.fetchHourlyAqi(lat, lng, today),
            _api.fetchHourlyWeather(lat, lng, today).then(raws),
          ]);
          bool recent(Map<String, dynamic> m) {
            final t = parseApiDate(m['date']);
            return t != null && !t.isBefore(from);
          }
          aqi = r[0].where(recent).toList();
          weather = r[1].where(recent).toList();
        case ViewMode.daily:
          final from = now.subtract(const Duration(hours: 24));
          final r = await Future.wait([
            _api.fetchHourlyAqiRange(lat, lng, dateOnly(from), today),
            _api
                .fetchHourlyWeather(lat, lng, today)
                .then(raws)
                .catchError((_) => <Map<String, dynamic>>[]),
          ]);
          bool inWindow(Map<String, dynamic> m) {
            final t = parseApiDate(m['date']);
            return t != null && !t.isBefore(from) && !t.isAfter(now);
          }
          int byDate(Map<String, dynamic> x, Map<String, dynamic> y) =>
              parseApiDate(x['date'])!.compareTo(parseApiDate(y['date'])!);
          aqi = r[0].where(inWindow).toList()..sort(byDate);
          weather = r[1].where(inWindow).toList()..sort(byDate);
        case ViewMode.weekly:
        case ViewMode.monthly:
          final back = mode == ViewMode.weekly ? 7 : 30;
          final days = mode == ViewMode.weekly ? 7 : 30;
          aqi = await _api.fetchHourlyAqiRange(lat, lng, dateOnly(subDays(now, back)), today);
          final perDay = await runPooled([
            for (var i = 0; i < days; i++)
              () => _api.fetchHourlyWeather(lat, lng, dateOnly(subDays(now, i))).then(raws),
          ]);
          weather = [for (final d in perDay) ...d];
      }
      if (!mounted || token != _token) return;
      setState(() {
        _rows = _merge(mode, aqi, weather);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _rows = [];
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static List<_Row> _merge(
      ViewMode mode, List<Map<String, dynamic>> aqi, List<Map<String, dynamic>> weather) {
    final daily = mode == ViewMode.weekly || mode == ViewMode.monthly;
    final fmt = DateFormat(daily ? 'MMM dd' : 'HH:mm');
    final map = <String, _Row>{};
    if (daily) {
      for (final d in dailyAqiRows(aqi)) {
        final row = map[d.label] = _Row(d.label, d.latest);
        row.values.addAll({
          'aqi': d.aqi.toDouble(),
          'pm2_5': d.pm25,
          'pm10': d.pm10,
          'co': d.co,
          'no2': d.no2,
          'so2': d.so2,
          'o3': d.o3,
        });
        row.trend = d.trend;
        row.trendPercentage = d.trendPercentage;
      }
    } else {
      for (final r in aqi) {
        final t = parseApiDate(r['date']);
        if (t == null) continue;
        final row = map.putIfAbsent(fmt.format(t), () => _Row(fmt.format(t), t));
        for (final k in ['aqi', 'pm2_5', 'pm10', 'co', 'no2', 'so2', 'o3']) {
          row.values[k] = toDouble(r[k]);
        }
        row.trend = toStr(r['trend']);
        row.trendPercentage = toDouble(r['trend_percentage']);
      }
    }
    for (final r in weather) {
      final t = parseApiDate(r['date']);
      if (t == null) continue;
      final row = map.putIfAbsent(fmt.format(t), () => _Row(fmt.format(t), t));
      for (final k in _weatherKeys) {
        row.values[k] = toDouble(r[k]);
      }
    }
    return map.values.toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  }

  void _setMode(ViewMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _load();
  }

  DateTime get _maxDate {
    final t = today();
    return widget.args.maxDate.isBefore(t) ? widget.args.maxDate : t;
  }

  /// Like the website, this only changes the date label; the data windows
  /// are always relative to today.
  void _shiftDate(int delta) {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + delta);
    if (delta < 0 && d.isBefore(widget.args.startDate)) return;
    if (delta > 0 && d.isAfter(_maxDate)) {
      if (_selectedDate.isBefore(_maxDate)) setState(() => _selectedDate = _maxDate);
      return;
    }
    setState(() => _selectedDate = d);
  }

  static String _f(double? v, [int digits = 2]) =>
      v == null ? 'N/A' : v.toStringAsFixed(digits);

  String _trend(_Row r) => r.trend == null
      ? 'N/A'
      : '${r.trend} ${r.trendPercentage == null ? '' : '${jsNum(r.trendPercentage!)}%'}';

  Future<void> _export() async {
    if (_rows.isEmpty) return;
    try {
      await exportToExcel(
        fileName: 'AQI_Data_${ymd(_selectedDate)}.xlsx',
        headers: [
          'Time', 'AQI', 'PM2.5 (µg/m³)', 'PM10 (µg/m³)', 'CO (ppm)', 'NO₂ (µg/m³)',
          'SO₂ (µg/m³)', 'O₃ (µg/m³)', 'Temperature (°C)', 'Humidity (%)',
          'Wind Speed (km/h)', 'UV Index', 'Trend',
        ],
        rows: [
          for (final r in _rows)
            [
              r.time,
              r.values['aqi'] == null ? 'N/A' : jsNum(r.values['aqi']!),
              for (final k in ['pm2_5', 'pm10', 'co', 'no2', 'so2', 'o3']) _f(r.values[k]),
              _f(r.values['temperature'], 1),
              _f(r.values['humidity'], 1),
              _f(r.values['wind_speed'], 1),
              _f(r.values['uv_index'], 1),
              _trend(r),
            ],
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  int get _labelEvery => switch (_mode) {
        ViewMode.live => 5,
        ViewMode.daily => 3,
        ViewMode.weekly => 1,
        ViewMode.monthly => 3,
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final selected = [for (final p in _params) if (_selected.contains(p.$1)) p];
    final a = widget.args;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AQI Analysis Results'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: rows.isEmpty || _loading ? null : _export,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export Data'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            a.placeName ?? 'Lat: ${a.latitude.toStringAsFixed(4)}, Lon: ${a.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          if (_mode == ViewMode.daily) ...[
            HourlyAqiTiles(latitude: a.latitude, longitude: a.longitude),
            const SizedBox(height: 16),
          ],
          _dateRow(),
          const SizedBox(height: 14),
          Center(
            child: ModeTabs<ViewMode>(
              values: ViewMode.values,
              selected: _mode,
              label: (m) => m.label,
              onChanged: _setMode,
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Parameters',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: () => setState(() {
                  _multiple = !_multiple;
                  if (!_multiple && _selected.length > 1) {
                    final first = _params.firstWhere((p) => _selected.contains(p.$1)).$1;
                    _selected
                      ..clear()
                      ..add(first);
                  }
                }),
                child: Text(_multiple ? 'Multiple' : 'Single'),
              ),
              TextButton(
                onPressed: () => setState(() => _selected.addAll(_params.map((p) => p.$1))),
                child: const Text('Select All'),
              ),
              TextButton(
                onPressed: () => setState(_selected.clear),
                child: const Text('Clear'),
              ),
            ]),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, label, color) in _params)
                FilterChip(
                  label: Text(label),
                  selected: _selected.contains(key),
                  selectedColor: color.withValues(alpha: 0.35),
                  backgroundColor: AppColors.card,
                  side: BorderSide(color: _selected.contains(key) ? color : AppColors.border),
                  showCheckmark: false,
                  onSelected: (on) => setState(() {
                    if (!_multiple) {
                      _selected
                        ..clear()
                        ..add(key);
                    } else if (on) {
                      _selected.add(key);
                    } else {
                      _selected.remove(key);
                    }
                  }),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const LoadingBox(height: 240)
          else if (_error != null)
            ErrorBox(message: _error!, onRetry: _load)
          else if (rows.isEmpty)
            const EmptyBox(message: 'No hourly records returned for this period')
          else ...[
            SectionCard(
              title: 'Parameter Trend',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.show_chart, size: 16)),
                    ButtonSegment(value: true, icon: Icon(Icons.bar_chart, size: 16)),
                  ],
                  selected: {_bar},
                  onSelectionChanged: (s) => setState(() => _bar = s.first),
                ),
              ]),
              child: selected.isEmpty
                  ? const EmptyBox(message: 'Select at least one parameter')
                  : TrendChart(
                      bar: _bar,
                      height: 300,
                      labelEvery: _labelEvery,
                      xLabels: [for (final r in rows) r.time],
                      series: [
                        for (final (key, label, color) in selected)
                          ChartSeries(label, color, [for (final r in rows) r.values[key]]),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Hourly Records (${rows.length})',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 36,
                  columnSpacing: 18,
                  columns: const [
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('AQI'), numeric: true),
                    DataColumn(label: Text('PM2.5'), numeric: true),
                    DataColumn(label: Text('PM10'), numeric: true),
                    DataColumn(label: Text('CO'), numeric: true),
                    DataColumn(label: Text('NO₂'), numeric: true),
                    DataColumn(label: Text('SO₂'), numeric: true),
                    DataColumn(label: Text('O₃'), numeric: true),
                    DataColumn(label: Text('Temp')),
                    DataColumn(label: Text('Humidity')),
                    DataColumn(label: Text('Wind')),
                    DataColumn(label: Text('UV'), numeric: true),
                    DataColumn(label: Text('Trend')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(cells: [
                        DataCell(Text(r.time)),
                        DataCell(Text(r.values['aqi'] == null ? 'N/A' : jsNum(r.values['aqi']!))),
                        for (final k in ['pm2_5', 'pm10', 'co', 'no2', 'so2', 'o3'])
                          DataCell(Text(_f(r.values[k]))),
                        DataCell(Text(r.values['temperature'] == null
                            ? 'N/A'
                            : '${_f(r.values['temperature'], 1)}°C')),
                        DataCell(Text(r.values['humidity'] == null
                            ? 'N/A'
                            : '${_f(r.values['humidity'], 1)}%')),
                        DataCell(Text(r.values['wind_speed'] == null
                            ? 'N/A'
                            : '${_f(r.values['wind_speed'], 1)} km/h')),
                        DataCell(Text(_f(r.values['uv_index'], 1))),
                        DataCell(Text(_trend(r))),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateRow() => Container(
        decoration: AppDecorations.card(radius: 14),
        child: Row(children: [
          TextButton.icon(
            onPressed: _selectedDate.isAfter(widget.args.startDate)
                ? () => _shiftDate(-1)
                : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          Expanded(
            child: Text(DateFormat('MMMM dd, yyyy').format(_selectedDate),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: _selectedDate.isBefore(_maxDate) ? () => _shiftDate(1) : null,
            child: const Row(children: [Text('Next'), Icon(Icons.chevron_right)]),
          ),
        ]),
      );
}
