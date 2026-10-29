import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/aqi.dart';
import '../models/json_utils.dart';
import '../services/api_client.dart';
import '../utils/date_utils.dart';
import '../widgets/aqi_pollutant_donut.dart';
import '../widgets/dark_osm_tiles.dart';
import '../widgets/home_aqi_dashboard.dart';

enum HomeAqiDetailsMode { overview, history, prediction }

/// Separate details page opened from the home AQI gauge / History·Prediction bar.
/// Pollutant cards use the live `/aqi` record; the chart uses real hourly API rows.
class HomeAqiDetailsScreen extends StatefulWidget {
  const HomeAqiDetailsScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.mode,
    this.initialRecord,
    this.placeName,
  });

  final double latitude;
  final double longitude;
  final HomeAqiDetailsMode mode;
  final AqiRecord? initialRecord;
  final String? placeName;

  @override
  State<HomeAqiDetailsScreen> createState() => _HomeAqiDetailsScreenState();
}

class _HomeAqiDetailsScreenState extends State<HomeAqiDetailsScreen> {
  final _api = ApiClient.instance;

  AqiRecord? _record;
  bool _loadingRecord = false;
  String? _recordError;

  List<_HourPoint> _points = [];
  bool _loadingChart = false;
  String? _chartError;

  String? _analysis;
  bool _loadingAnalysis = false;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    _record = widget.initialRecord;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Overview = Design #4 donut only (live /aqi). History/Prediction load charts.
    await Future.wait([
      if (_record == null) _loadRecord(),
      if (widget.mode != HomeAqiDetailsMode.overview) _loadChart(),
      if (widget.mode == HomeAqiDetailsMode.prediction) _loadAnalysis(),
    ]);
  }

  Future<void> _loadRecord() async {
    setState(() {
      _loadingRecord = true;
      _recordError = null;
    });
    try {
      final raw =
          await _api.fetchAqi(widget.latitude, widget.longitude);
      if (!mounted) return;
      setState(() {
        _record = AqiRecord.fromJson(raw);
        _loadingRecord = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recordError = e.toString();
        _loadingRecord = false;
      });
    }
  }

  Future<void> _loadChart() async {
    setState(() {
      _loadingChart = true;
      _chartError = null;
    });
    try {
      final now = DateTime.now();
      final today = dateOnly(now);
      List<Map<String, dynamic>> raw;
      if (widget.mode == HomeAqiDetailsMode.history) {
        raw = await _api.fetchHourlyAqiRange(
          widget.latitude,
          widget.longitude,
          dateOnly(now.subtract(const Duration(hours: 24))),
          today,
        );
      } else {
        raw = await _api.fetchHourlyAqi(
          widget.latitude,
          widget.longitude,
          today,
        );
      }

      var points = <_HourPoint>[];
      for (final m in raw) {
        final aqi = toDouble(m['aqi']);
        final t = parseApiDate(m['date']);
        if (aqi == null || t == null) continue;
        points.add(_HourPoint(time: t, aqi: aqi));
      }
      points.sort((a, b) => a.time.compareTo(b.time));

      if (widget.mode == HomeAqiDetailsMode.prediction) {
        // Only keep hours at/after now that the API actually returned — never invent.
        points = points.where((p) => !p.time.isBefore(now)).toList();
      } else if (widget.mode == HomeAqiDetailsMode.overview) {
        // Recent slice for a compact overview chart.
        if (points.length > 12) {
          points = points.sublist(points.length - 12);
        }
      } else if (widget.mode == HomeAqiDetailsMode.history) {
        final from = now.subtract(const Duration(hours: 24));
        points = points.where((p) => !p.time.isBefore(from)).toList();
      }

      if (!mounted) return;
      setState(() {
        _points = points;
        _loadingChart = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chartError = e.toString();
        _loadingChart = false;
      });
    }
  }

  Future<void> _loadAnalysis() async {
    setState(() {
      _loadingAnalysis = true;
      _analysisError = null;
    });
    try {
      final text = await _api.fetchAqiAnalysis(
        widget.latitude,
        widget.longitude,
        today(),
      );
      if (!mounted) return;
      setState(() {
        _analysis = text;
        _loadingAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisError = e.toString();
        _loadingAnalysis = false;
      });
    }
  }

  String get _title => switch (widget.mode) {
        HomeAqiDetailsMode.overview => 'AQI',
        HomeAqiDetailsMode.history => 'AQI History',
        HomeAqiDetailsMode.prediction => 'AQI Prediction',
      };

  String? get _subtitle => switch (widget.mode) {
        HomeAqiDetailsMode.overview => 'Pollutant Distribution',
        _ => widget.placeName,
      };

  String get _chartTitle => switch (widget.mode) {
        HomeAqiDetailsMode.overview => 'AQI (recent hours)',
        HomeAqiDetailsMode.history => 'AQI (last 24 hours)',
        HomeAqiDetailsMode.prediction => 'AQI (upcoming hours from API)',
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final short = MediaQuery.sizeOf(context).height < 720;
    final bg = LightOsmTileLayer.background;
    final showAnalysis = widget.mode == HomeAqiDetailsMode.prediction;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF1F5F9),
              const Color(0xFFF8FAFC),
              bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    4,
                    short ? 0 : 2,
                    8,
                    widget.mode == HomeAqiDetailsMode.overview
                        ? 0
                        : (short ? 2 : 4)),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Color(0xFF0F172A)),
                    ),
                    // Overview embeds title/badge inside the distribution card.
                    if (widget.mode != HomeAqiDetailsMode.overview)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title,
                              style: TextStyle(
                                fontSize: short ? 18 : 20,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            if (_subtitle != null && _subtitle!.isNotEmpty)
                              Text(
                                _subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _loadRecord();
                        if (widget.mode != HomeAqiDetailsMode.overview) {
                          _loadChart();
                        }
                        if (showAnalysis) _loadAnalysis();
                      },
                      icon: const Icon(Icons.refresh_rounded,
                          color: LightOsmTileLayer.accent),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      wide ? 24 : 16, 0, wide ? 24 : 16, short ? 8 : 12),
                  child: widget.mode == HomeAqiDetailsMode.overview
                      ? _overviewDonutBody(wide: wide, short: short)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _pollutantSection(compact: short),
                            SizedBox(height: short ? 10 : 14),
                            Expanded(child: _chartSection(compact: short)),
                            if (showAnalysis) ...[
                              SizedBox(height: short ? 8 : 10),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height *
                                          0.18,
                                ),
                                child: SingleChildScrollView(
                                  child: _analysisSection(compact: short),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reference layout: 3D donut + pollutant details + footer accent.
  Widget _overviewDonutBody({required bool wide, required bool short}) {
    if (_loadingRecord && _record == null) {
      return const Center(
        child: CircularProgressIndicator(color: LightOsmTileLayer.accent),
      );
    }
    if (_recordError != null && _record == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_recordError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB91C1C))),
            TextButton(
              onPressed: _loadRecord,
              child: const Text('Retry',
                  style: TextStyle(color: LightOsmTileLayer.accent)),
            ),
          ],
        ),
      );
    }
    final record = _record;
    if (record == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final panel = AqiPollutantDistributionPanel(
          record: record,
          compact: short || constraints.maxHeight < 680,
          showInlineHeader: true,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            child: panel,
          ),
        );
      },
    );
  }

  Widget _pollutantSection({required bool compact}) {
    if (_loadingRecord && _record == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: LightOsmTileLayer.accent),
          ),
        ),
      );
    }
    if (_recordError != null && _record == null) {
      return _GlassPanel(
        compact: compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_recordError!,
                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13)),
            TextButton(
              onPressed: _loadRecord,
              child: const Text('Retry',
                  style: TextStyle(color: LightOsmTileLayer.accent)),
            ),
          ],
        ),
      );
    }
    final record = _record;
    if (record == null) return const SizedBox.shrink();

    // Strictly card-free: no panel, border, or shadow — typography + spacing only.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pollutants',
          style: TextStyle(
            fontSize: compact ? 15 : 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Values from /aqi for this location',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
        SizedBox(height: compact ? 10 : 12),
        for (var i = 0; i < kHomePollutantFields.length; i += 2) ...[
          if (i > 0) ...[
            SizedBox(height: compact ? 7 : 9),
            Divider(
              height: 1,
              thickness: 1,
              color: LightOsmTileLayer.accent.withValues(alpha: 0.12),
            ),
            SizedBox(height: compact ? 7 : 9),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: _PollutantTextLine(
                  label: kHomePollutantFields[i].$2,
                  unit: kHomePollutantFields[i].$3,
                  value: _pollutantValue(record, kHomePollutantFields[i].$1),
                  compact: compact,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < kHomePollutantFields.length
                    ? _PollutantTextLine(
                        label: kHomePollutantFields[i + 1].$2,
                        unit: kHomePollutantFields[i + 1].$3,
                        value: _pollutantValue(
                            record, kHomePollutantFields[i + 1].$1),
                        compact: compact,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  double? _pollutantValue(AqiRecord record, String key) {
    final v = record.value(key);
    return switch (key) {
      'pm2_5' => record.pm25 ?? v,
      'pm10' => record.pm10 ?? v,
      'no2' => record.no2 ?? v,
      'so2' => record.so2 ?? v,
      'o3' => record.o3 ?? v,
      'co' => record.co ?? v,
      _ => v,
    };
  }

  Widget _chartSection({required bool compact}) {
    return _GlassPanel(
      compact: compact,
      expand: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _chartTitle,
            style: TextStyle(
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Expanded(
            child: _loadingChart
                ? const Center(
                    child: CircularProgressIndicator(
                        color: LightOsmTileLayer.accent),
                  )
                : _chartError != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_chartError!,
                              style: const TextStyle(
                                  color: Color(0xFFB91C1C), fontSize: 13)),
                          TextButton(
                            onPressed: _loadChart,
                            child: const Text('Retry chart',
                                style: TextStyle(
                                    color: LightOsmTileLayer.accent)),
                          ),
                        ],
                      )
                    : _points.isEmpty
                        ? Center(
                            child: Text(
                              widget.mode == HomeAqiDetailsMode.prediction
                                  ? 'No upcoming hourly AQI points in the API response.'
                                  : 'No hourly AQI data available.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFF64748B), fontSize: 13),
                            ),
                          )
                        : _AqiBarChart(points: _points, compact: compact),
          ),
        ],
      ),
    );
  }

  Widget _analysisSection({required bool compact}) {
    return _GlassPanel(
      compact: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analysis',
            style: TextStyle(
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'From /aqi/analyze — text as returned by the API',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          if (_loadingAnalysis)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    color: LightOsmTileLayer.accent),
              ),
            )
          else if (_analysisError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_analysisError!,
                    style: const TextStyle(
                        color: Color(0xFFB91C1C), fontSize: 13)),
                TextButton(
                  onPressed: _loadAnalysis,
                  child: const Text('Retry analysis',
                      style: TextStyle(color: LightOsmTileLayer.accent)),
                ),
              ],
            )
          else
            Text(
              _analysis ?? '—',
              style: TextStyle(
                fontSize: compact ? 12.5 : 13.5,
                height: 1.4,
                color: const Color(0xFF0F172A),
              ),
            ),
        ],
      ),
    );
  }
}

class _HourPoint {
  _HourPoint({required this.time, required this.aqi});
  final DateTime time;
  final double aqi;
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.compact = false,
    this.expand = false,
  });
  final Widget child;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: LightGlassSurface.card(radius: compact ? 16 : 18),
          child: child,
        ),
      ),
    );
    return expand ? SizedBox.expand(child: panel) : panel;
  }
}

class _PollutantTextLine extends StatelessWidget {
  const _PollutantTextLine({
    required this.label,
    required this.unit,
    required this.value,
    required this.compact,
  });

  final String label, unit;
  final double? value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = value == null || value!.isNaN
        ? '—'
        : value!.toStringAsFixed(value!.abs() >= 100 ? 0 : 1);

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              fontSize: compact ? 12.5 : 13.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          TextSpan(
            text: text,
            style: TextStyle(
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          TextSpan(
            text: ' $unit',
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w600,
              color: LightOsmTileLayer.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _AqiBarChart extends StatelessWidget {
  const _AqiBarChart({required this.points, this.compact = false});
  final List<_HourPoint> points;
  final bool compact;

  static const _teal = Color(0xFF14B8A6);
  static const _warm = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('ha');
    final maxAqi = points
        .map((p) => p.aqi)
        .fold<double>(50, (a, b) => a > b ? a : b)
        .clamp(50, 400);
    // Room above bars for value labels.
    final maxY = maxAqi * 1.22;
    final showValues = points.length <= 12;
    final barW = points.length > 18
        ? (compact ? 5.0 : 7.0)
        : points.length > 10
            ? (compact ? 10.0 : 14.0)
            : (compact ? 14.0 : 18.0);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        groupsSpace: 6,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xF20F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final p = points[group.x.toInt()];
              return BarTooltipItem(
                '${fmt.format(p.time)}\nAQI ${p.aqi.round()}',
                const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: showValues,
              reservedSize: compact ? 18 : 22,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= points.length || v != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${points[i].aqi.round()}',
                    style: TextStyle(
                      fontSize: compact ? 9 : 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compact ? 28 : 32,
              interval: _niceInterval(maxY),
              getTitlesWidget: (v, _) {
                if (v < 0 || v > maxY) return const SizedBox.shrink();
                return Text(
                  v.toInt().toString(),
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compact ? 22 : 26,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                final step = (points.length / 6).ceil().clamp(1, 6);
                if (i % step != 0 && i != points.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: EdgeInsets.only(top: compact ? 4 : 6),
                  child: Text(
                    fmt.format(points[i].time),
                    style: TextStyle(
                      fontSize: compact ? 9 : 10,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _niceInterval(maxY),
          getDrawingHorizontalLine: (_) => FlLine(
            color: const Color(0xFF14B8A6).withValues(alpha: 0.10),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].aqi,
                  width: barW,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [_teal, Color(0xFF5EEAD4), _warm],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  static double _niceInterval(double maxY) {
    if (maxY <= 60) return 10;
    if (maxY <= 120) return 20;
    if (maxY <= 250) return 50;
    return 100;
  }
}
