import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/aqi.dart';
import '../models/json_utils.dart';
import '../services/api_client.dart';
import '../utils/date_utils.dart';
import '../widgets/aqi_pollutant_donut.dart';
import '../widgets/aqi_pollutant_pills_chart.dart';
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
    this.isSatellite = true,
  });

  final double latitude;
  final double longitude;
  final HomeAqiDetailsMode mode;
  final AqiRecord? initialRecord;
  final String? placeName;
  final bool isSatellite;

  @override
  State<HomeAqiDetailsScreen> createState() => _HomeAqiDetailsScreenState();
}

class _HomeAqiDetailsScreenState extends State<HomeAqiDetailsScreen> {
  final _api = ApiClient.instance;

  AqiRecord? _record;
  bool _loadingRecord = false;
  String? _recordError;

  List<AqiHourSample> _samples = [];
  bool _loadingChart = false;
  String? _chartError;
  String _selectedPollutantKey = kHomePollutantFields.first.$1;

  /// Local History/Prediction mode (starts from the home-bar selection).
  late bool _trendIsHistory;

  @override
  void initState() {
    super.initState();
    _record = widget.initialRecord;
    _trendIsHistory = widget.mode != HomeAqiDetailsMode.prediction;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Overview = pollutant donut (live /aqi). History/Prediction = glass chart.
    await Future.wait([
      if (_record == null) _loadRecord(),
      if (widget.mode != HomeAqiDetailsMode.overview) _loadChart(),
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
      final todayD = dateOnly(now);
      final tomorrowD = todayD.add(const Duration(days: 1));
      final yesterdayD = todayD.subtract(const Duration(days: 1));

      final raw = <Map<String, dynamic>>[];
      if (_trendIsHistory) {
        // Cover last 6h across a midnight boundary if needed.
        raw.addAll(await _api.fetchHourlyAqiRange(
          widget.latitude,
          widget.longitude,
          yesterdayD,
          todayD,
        ));
      } else {
        // Prediction: today (+ tomorrow near end of day) — never invent points.
        raw.addAll(await _api.fetchHourlyAqi(
          widget.latitude,
          widget.longitude,
          todayD,
        ));
        if (now.hour >= 18) {
          try {
            raw.addAll(await _api.fetchHourlyAqi(
              widget.latitude,
              widget.longitude,
              tomorrowD,
            ));
          } catch (_) {
            // Tomorrow may be unavailable; keep today's future hours only.
          }
        }
      }

      var samples = <AqiHourSample>[];
      for (final m in raw) {
        final t = parseApiDate(m['date']);
        if (t == null) continue;
        final values = <String, double>{};
        for (final (key, _, _) in kHomePollutantFields) {
          final v = toDouble(m[key]) ?? toDouble(m['${key}_0to3m']);
          if (v != null && !v.isNaN) values[key] = v;
        }
        if (values.isEmpty) continue;
        samples.add(AqiHourSample(time: t, values: values));
      }
      samples.sort((a, b) => a.time.compareTo(b.time));

      final seen = <String>{};
      samples = samples.where((s) {
        final k = s.time.toIso8601String();
        if (seen.contains(k)) return false;
        seen.add(k);
        return true;
      }).toList();

      if (_trendIsHistory) {
        final from = now.subtract(const Duration(hours: 6));
        samples = samples
            .where((s) =>
                !s.time.isBefore(from) &&
                !s.time.isAfter(now.add(const Duration(minutes: 30))))
            .toList();
        if (samples.length > 6) {
          samples = samples.sublist(samples.length - 6);
        }
      } else {
        final until = now.add(const Duration(hours: 6, minutes: 30));
        samples = samples
            .where((s) =>
                !s.time.isBefore(now.subtract(const Duration(minutes: 20))) &&
                !s.time.isAfter(until))
            .toList();
        if (samples.length > 6) {
          samples = samples.sublist(0, 6);
        }
      }

      if (!mounted) return;
      setState(() {
        _samples = samples;
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

  String get _title {
    if (widget.mode == HomeAqiDetailsMode.overview) return 'AQI';
    return _trendIsHistory ? 'History' : 'Prediction';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final short = MediaQuery.sizeOf(context).height < 720;
    final overview = widget.mode == HomeAqiDetailsMode.overview;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live interactive map remains visible underneath via MapBackedPageRoute.
          // Zero background fill opacity and no blur overlays.
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      14, short ? 4 : 8, 14, overview ? 0 : 4),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.isSatellite
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.isSatellite
                                ? Colors.white.withValues(alpha: 0.35)
                                : const Color(0xFFCBD5E1),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            size: 26,
                            color: widget.isSatellite
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (overview)
                        const Spacer()
                      else
                        Expanded(
                          child: Text(
                            _title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: short ? 20 : 22,
                              fontWeight: FontWeight.w800,
                              color: widget.isSatellite
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              shadows: widget.isSatellite
                                  ? [
                                      const Shadow(
                                        color: Colors.black54,
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.isSatellite
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.isSatellite
                                ? Colors.white.withValues(alpha: 0.35)
                                : const Color(0xFFCBD5E1),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'Refresh',
                          onPressed: () {
                            _loadRecord();
                            if (!overview) _loadChart();
                          },
                          icon: Icon(
                            Icons.refresh_rounded,
                            size: 22,
                            color: widget.isSatellite
                                ? const Color(0xFF14B8A6)
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: overview
                      ? Padding(
                          padding: EdgeInsets.fromLTRB(
                              wide ? 24 : 16, 0, wide ? 24 : 16, short ? 4 : 6),
                          child: _overviewDonutBody(wide: wide, short: short),
                        )
                      : AqiPollutantPillsChart(
                          isHistory: _trendIsHistory,
                          selectedKey: _selectedPollutantKey,
                          isSatellite: widget.isSatellite,
                          record: _record,
                          placeName: widget.placeName,
                          onSelect: (key) =>
                              setState(() => _selectedPollutantKey = key),
                          samples: _samples,
                          loading: _loadingChart,
                          error: _chartError,
                          onRetry: _loadChart,
                          onHistoryChanged: (history) {
                            setState(() => _trendIsHistory = history);
                            _loadChart();
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
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
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 640.0;
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final compact = short || h < 720;
        // ~13% larger than prior clamp (148–168 / 186).
        final donut = (h * 0.25).clamp(168.0, compact ? 190.0 : 212.0);
        final maxW = math.min(w, 420.0);

        // Header stays top; pack donut → list → status tightly. Remaining
        // height is shared as small breathing room under the status only.
        return SizedBox(
          height: h,
          width: w,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: maxW,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AqiPollutantDistributionPanel(
                      record: record,
                      compact: compact,
                      showInlineHeader: true,
                      donutSize: donut,
                      isSatellite: widget.isSatellite,
                    ),
                    SizedBox(height: math.min(16.0, h * 0.025)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
