import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/period_logic.dart';
import '../models/weather.dart';
import '../services/api_client.dart';
import '../services/excel_export.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import '../widgets/common.dart';
import '../widgets/detail_widgets.dart';
import 'analysis_screen.dart';
import 'aqi_detail_screen.dart';

class WeatherDetailScreen extends StatefulWidget {
  const WeatherDetailScreen({super.key, required this.args});
  final DetailArgs args;

  @override
  State<WeatherDetailScreen> createState() => _WeatherDetailScreenState();
}

class _WeatherDetailScreenState extends State<WeatherDetailScreen> {
  final _api = ApiClient.instance;
  late DateTime _date = widget.args.date;

  Fetched<List<HourlyWeather>>? _hourly;
  bool _loadingHourly = false;
  int _hourlyToken = 0;

  bool get _weekly => widget.args.mode == ViewMode.weekly;
  bool get _daily => widget.args.mode == ViewMode.daily;

  /// Weekly opens on today − 6 … today (WeatherSection.jsx).
  DateTime get _startDate =>
      _weekly ? dateOnly(subDays(DateTime.now(), 6)) : widget.args.startDate;

  DateTime get _maxDate {
    final t = today();
    final end = _weekly ? t : widget.args.maxDate;
    return end.isBefore(t) ? end : t;
  }

  @override
  void initState() {
    super.initState();
    _loadHourly();
  }

  Future<void> _loadHourly() async {
    final token = ++_hourlyToken;
    setState(() => _loadingHourly = true);
    final r = await Fetched.of(
        _api.fetchHourlyWeather(widget.args.latitude, widget.args.longitude, _date));
    if (!mounted || token != _hourlyToken) return;
    setState(() {
      _hourly = r;
      _loadingHourly = false;
    });
  }

  void _shiftDate(int delta) {
    var d = DateTime(_date.year, _date.month, _date.day + delta);
    if (delta < 0 && d.isBefore(_startDate)) return;
    if (delta > 0 && d.isAfter(_maxDate)) {
      if (!_date.isBefore(_maxDate)) return;
      d = _maxDate;
    }
    setState(() => _date = d);
    _loadHourly();
  }

  Future<void> _export() async {
    final rows = _hourly?.data ?? const <HourlyWeather>[];
    if (rows.isEmpty) return;
    try {
      await exportToExcel(
        fileName: 'Weather_Data_${ymd(_date)}.xlsx',
        headers: _columns,
        rows: [for (final r in rows) _cells(r)],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  static const _columns = [
    'Time', 'Temp', 'Feels like', 'Humidity', 'Wind speed', 'Wind dir',
    'Wind gusts', 'UV index', 'Precipitation', 'Cloud cover', 'Visibility',
    'Pressure', 'Condition', 'Source',
  ];

  List<Object?> _cells(HourlyWeather r) => [
        r.date == null ? null : DateFormat('yyyy-MM-dd HH:mm').format(r.date!),
        r.temperature, r.feelsLike, r.humidity, r.windSpeed,
        r.windDirectionCardinal ??
            (r.windDirection == null ? null : '${r.windDirection!.round()}°'),
        r.windGusts, r.uvIndex, r.precipitation, r.cloudCover, r.visibility,
        r.pressure, r.condition, r.dataSource,
      ];

  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    final hourly = _hourly?.data ?? const <HourlyWeather>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Analysis Results'),
        actions: [
          TextButton.icon(
            onPressed: hourly.isEmpty || _loadingHourly ? null : _export,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Export Data'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            a.placeName ??
                '${a.latitude.toStringAsFixed(4)}, ${a.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          if (_daily)
            HourlyAqiTiles(latitude: a.latitude, longitude: a.longitude)
          else
            WeatherCalendar(
              latitude: a.latitude,
              longitude: a.longitude,
              selectedDate: _date,
              weekStart: _weekly ? _startDate : null,
              weekEnd: _weekly ? today() : null,
            ),
          const SizedBox(height: 12),
          Container(
            decoration: AppDecorations.card(radius: 14),
            child: Row(children: [
              TextButton.icon(
                onPressed: _date.isAfter(_startDate) ? () => _shiftDate(-1) : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              Expanded(
                child: Text(prettyDate(_date),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _date.isBefore(_maxDate) ? () => _shiftDate(1) : null,
                child: const Row(children: [Text('Next'), Icon(Icons.chevron_right)]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loadingHourly)
            const LoadingBox(height: 200)
          else if (_hourly?.error != null)
            ErrorBox(message: _hourly!.error!, onRetry: _loadHourly)
          else if (hourly.isEmpty)
            const EmptyBox(message: 'No hourly weather records for this date')
          else ...[
            _metrics(hourly),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Hourly Weather (${hourly.length})',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 36,
                  columnSpacing: 16,
                  columns: [for (final c in _columns) DataColumn(label: Text(c))],
                  rows: [
                    for (final r in hourly)
                      DataRow(cells: [
                        DataCell(Text(r.date == null ? '—' : DateFormat('HH:mm').format(r.date!))),
                        for (final v in _cells(r).skip(1))
                          DataCell(Text(v == null
                              ? '—'
                              : v is double
                                  ? v.toStringAsFixed(1)
                                  : v.toString())),
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

  /// Metric cards showing the latest hourly record for the selected date.
  Widget _metrics(List<HourlyWeather> hourly) {
    final r = hourly.last;
    final items = <(IconData, String, String)>[
      (Icons.thermostat, 'Temperature', fmt(r.temperature, unit: '°C')),
      (Icons.device_thermostat, 'Feels like', fmt(r.feelsLike, unit: '°C')),
      (Icons.water_drop_outlined, 'Humidity', fmt(r.humidity, unit: '%')),
      (Icons.air, 'Wind', '${fmt(r.windSpeed)} ${r.windDirectionCardinal ?? ''}'),
      (Icons.storm_outlined, 'Gusts', fmt(r.windGusts)),
      (Icons.wb_sunny_outlined, 'UV index', fmt(r.uvIndex)),
      (Icons.cloud_outlined, 'Cloud cover', fmt(r.cloudCover, unit: '%')),
      (Icons.visibility_outlined, 'Visibility', fmt(r.visibility)),
      (Icons.speed, 'Pressure', fmt(r.pressure)),
      (Icons.umbrella_outlined, 'Precipitation', fmt(r.precipitation)),
    ];
    return SectionCard(
      title: 'Latest hour · ${r.date == null ? '' : DateFormat('HH:mm').format(r.date!)}'
          '${r.condition != null ? ' · ${r.condition}' : ''}',
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (icon, label, value) in items)
          Container(
            width: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
