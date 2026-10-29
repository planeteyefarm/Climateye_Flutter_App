import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/aqi.dart';
import '../models/period_logic.dart';
import '../models/weather.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import '../widgets/aqi_gauge.dart';
import '../widgets/aqi_report_card.dart';
import '../widgets/aqi_trend_chart.dart';
import '../widgets/common.dart';
import '../widgets/detail_widgets.dart';
import '../widgets/glass.dart';
import '../widgets/live_dashboard.dart';
import '../widgets/overview_cards.dart';
import '../widgets/period_cards.dart';
import 'aqi_detail_screen.dart';
import 'weather_detail_screen.dart';

export '../widgets/detail_widgets.dart' show runPooled;

enum ViewMode { live, daily, weekly, monthly }

extension ViewModeLabel on ViewMode {
  String get label => switch (this) {
        ViewMode.live => 'Live',
        ViewMode.daily => 'Last 24 Hrs',
        ViewMode.weekly => 'Weekly',
        ViewMode.monthly => 'Monthly',
      };
}

class AnalysisArgs {
  AnalysisArgs({
    required this.latitude,
    required this.longitude,
    required this.startDate,
    required this.endDate,
  });
  final double latitude, longitude;
  final DateTime startDate, endDate;
}

/// Captures a request result or its error message without throwing.
class Fetched<T> {
  Fetched.ok(this.data) : error = null;
  Fetched.err(this.error) : data = null;
  final T? data;
  final String? error;

  static Future<Fetched<T>> of<T>(Future<T> f) async {
    try {
      return Fetched.ok(await f);
    } catch (e) {
      return Fetched.err(e.toString());
    }
  }
}

enum AnalysisSection { overview, airQuality, weather, all }

/// The analysis dashboard, embedded in the map's analysis sheet. One
/// instance per run; [section] only filters which cards are shown, so mode,
/// date and fetched data are shared across the Area, Air Quality, Weather and
/// Results tabs.
class AnalysisPanel extends StatefulWidget {
  const AnalysisPanel({
    super.key,
    required this.args,
    this.section = AnalysisSection.all,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
    this.leading = const [],
    this.trailing = const [],
    this.onOpenSection,
  });
  final AnalysisArgs args;
  final AnalysisSection section;
  final EdgeInsetsGeometry padding;

  /// Extra widgets around the compact [AnalysisSection.overview] cards.
  final List<Widget> leading, trailing;

  /// Called when an overview control asks to show a fuller section.
  final ValueChanged<AnalysisSection>? onOpenSection;

  @override
  State<AnalysisPanel> createState() => _AnalysisPanelState();
}

class _AnalysisPanelState extends State<AnalysisPanel> {
  final _api = ApiClient.instance;

  late DateTime _viewDate = widget.args.endDate;
  ViewMode _mode = ViewMode.live;
  String? _placeName;

  /// Bumped on every mode/date change so late responses are dropped.
  int _token = 0;
  int _chartToken = 0;

  // Live
  bool _liveLoading = false;
  bool _liveDateNavigated = false;
  Fetched<Map<String, dynamic>>? _aqi;
  Fetched<WeatherSummary>? _weather;

  // Historical cards
  bool _cardsLoading = false;
  Fetched<AqiAggregate?>? _aqiCard;
  Fetched<WeatherAggregate?>? _weatherCard;
  String? _weatherWarning;

  // AQI Trend chart
  bool _chartLoading = false;
  String? _chartError;
  List<TrendPoint> _trend = const [];

  double get _lat => widget.args.latitude;
  double get _lng => widget.args.longitude;

  @override
  void initState() {
    super.initState();
    _load();
    _api.fetchPlaceName(_lat, _lng).then((n) {
      if (mounted && n != null) setState(() => _placeName = n);
    });
  }

  Future<void> _load() async {
    if (_mode == ViewMode.live) return _loadLive();
    await Future.wait([_loadCards(), _loadChart()]);
  }

  /// `/aqi` and `/weather` without a date on entry; with the viewing date
  /// once the user has used the date arrows.
  Future<void> _loadLive() async {
    final token = ++_token;
    final date = _liveDateNavigated ? _viewDate : null;
    setState(() => _liveLoading = true);
    final r = await Future.wait([
      Fetched.of(_api.fetchAqi(_lat, _lng, date)),
      Fetched.of(_api.fetchWeather(_lat, _lng, date)),
    ]);
    if (!mounted || token != _token) return;
    setState(() {
      _aqi = r[0] as Fetched<Map<String, dynamic>>;
      _weather = r[1] as Fetched<WeatherSummary>;
      _liveLoading = false;
    });
  }

  Future<void> _loadCards() async {
    final token = ++_token;
    final mode = _mode;
    final w = PeriodWindows(DateTime.now());
    setState(() {
      _cardsLoading = true;
      _aqiCard = null;
      _weatherCard = null;
      _weatherWarning = null;
    });
    final Future<List<Map<String, dynamic>>> aqiRequest;
    final List<DateTime> weatherDays;
    switch (mode) {
      case ViewMode.daily:
        aqiRequest = _api.fetchHourlyAqi(_lat, _lng, w.dailyCardsDate);
        weatherDays = [w.dailyCardsDate];
      case ViewMode.weekly:
        aqiRequest =
            _api.fetchHourlyAqiRange(_lat, _lng, w.weeklyAqiCard.start, w.weeklyAqiCard.end);
        weatherDays = w.weeklyWeatherDays;
      case ViewMode.monthly:
        aqiRequest =
            _api.fetchHourlyAqiRange(_lat, _lng, w.monthlyAqiCard.start, w.monthlyAqiCard.end);
        weatherDays = w.monthlyWeatherDays;
      case ViewMode.live:
        return;
    }
    final aqiF = Fetched.of(aqiRequest);
    final weatherF = runPooled([
      for (final d in weatherDays) () => Fetched.of(_api.fetchHourlyWeather(_lat, _lng, d)),
    ]);
    final aqi = await aqiF;
    final weather = await weatherF;
    if (!mounted || token != _token) return;

    final ok = weather.where((f) => f.data != null).toList();
    final failed = <String>[
      for (var i = 0; i < weather.length; i++)
        if (weather[i].error != null) '${ymd(weatherDays[i])}: ${weather[i].error}',
    ];
    setState(() {
      _aqiCard = aqi.error != null
          ? Fetched.err(aqi.error)
          : Fetched.ok(aggregateAqi(aqi.data!));
      if (ok.isEmpty) {
        _weatherCard = Fetched.err(failed.isEmpty ? 'No weather data' : failed.first);
      } else {
        _weatherCard = Fetched.ok(aggregateWeather([
          for (final f in ok)
            for (final h in f.data!) h.raw,
        ]));
        if (failed.isNotEmpty) {
          _weatherWarning = '${failed.length} of ${weatherDays.length} daily weather '
              'requests failed, so these averages exclude those days. First error: ${failed.first}';
        }
      }
      _cardsLoading = false;
    });
  }

  Future<void> _loadChart() async {
    final token = ++_chartToken;
    final mode = _mode;
    final now = DateTime.now();
    final w = PeriodWindows(now);
    final window = switch (mode) {
      ViewMode.daily => w.dailyChart,
      ViewMode.weekly => w.weeklyChart,
      ViewMode.monthly => w.monthlyChart,
      ViewMode.live => null,
    };
    if (window == null) return;
    setState(() {
      _chartLoading = true;
      _chartError = null;
      _trend = const [];
    });
    final r = await Fetched.of(_api.fetchHourlyAqiRange(_lat, _lng, window.start, window.end));
    if (!mounted || token != _chartToken) return;
    setState(() {
      _chartLoading = false;
      _chartError = r.error;
      final records = r.data ?? const <Map<String, dynamic>>[];
      _trend = switch (mode) {
        ViewMode.daily => dailyTrend(records, now),
        ViewMode.weekly => weeklyTrend(records),
        ViewMode.monthly => monthlyTrend(records, now),
        ViewMode.live => const [],
      };
    });
  }

  void _setMode(ViewMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _trend = const [];
    });
    _load();
  }

  DateTime get _maxDate {
    final t = today();
    return widget.args.endDate.isBefore(t) ? widget.args.endDate : t;
  }

  void _shiftDate(int delta) {
    if (_mode != ViewMode.live || _liveLoading) return;
    var d = DateTime(_viewDate.year, _viewDate.month, _viewDate.day + delta);
    if (d.isBefore(widget.args.startDate)) return;
    if (d.isAfter(_maxDate)) {
      if (!_viewDate.isBefore(_maxDate)) return;
      d = _maxDate;
    }
    setState(() {
      _viewDate = d;
      _liveDateNavigated = true;
    });
    _loadLive();
  }

  void _openAqiDetail() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AqiDetailScreen(args: _detailArgs()),
    ));
  }

  void _openWeatherDetail() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WeatherDetailScreen(args: _detailArgs()),
    ));
  }

  DetailArgs _detailArgs() => DetailArgs(
        latitude: _lat,
        longitude: _lng,
        startDate: widget.args.startDate,
        maxDate: widget.args.endDate,
        date: _viewDate,
        mode: _mode,
        placeName: _placeName,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.section == AnalysisSection.overview) {
      return ListView(
        padding: widget.padding,
        children: [
          ...widget.leading,
          _aqiOverview(),
          const SizedBox(height: 12),
          _weatherOverview(),
          ...widget.trailing,
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.mint,
      child: ListView(
        padding: widget.padding,
        children: [
          _areaContext(),
          const SizedBox(height: 12),
          _dateNav(),
          const SizedBox(height: 12),
          Center(
            child: ModeTabs<ViewMode>(
              values: ViewMode.values,
              selected: _mode,
              label: (m) => m.label,
              onChanged: _setMode,
            ),
          ),
          const SizedBox(height: 16),
          if (_mode == ViewMode.live)
            ..._liveContent()
          else
            ..._periodContent(),
        ],
      ),
    );
  }

  // ---------- Overview (Area tab) ----------

  String get _liveStatus => _liveDateNavigated ? ymd(_viewDate) : 'Live';

  Widget _aqiOverview() {
    final aqiMap = _aqi?.data;
    final record = aqiMap == null ? null : AqiRecord.fromJson(aqiMap);
    final Widget body;
    if (_aqi == null && _liveLoading) {
      body = const LoadingBox(height: 110);
    } else if (_aqi?.error != null) {
      body = ErrorBox(message: _aqi!.error!, onRetry: _loadLive);
    } else if (record == null) {
      body = const EmptyBox(message: 'No AQI data');
    } else {
      final v = record.aqi;
      final ring = AqiRing(aqi: (v == null || v.isNaN) ? null : v);
      final details = OutlinedButton(
        onPressed: _openAqiDetail,
        child: const Text('Detailed View'),
      );
      body = LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 520) {
          return Column(children: [
            ring,
            const SizedBox(height: 12),
            PollutantGrid(record: record, columns: 2),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: details),
          ]);
        }
        return Row(children: [
          ring,
          const SizedBox(width: 16),
          Expanded(child: PollutantGrid(record: record)),
          const SizedBox(width: 12),
          details,
        ]);
      });
    }
    return OverviewCard(
      title: 'AQI & Pollutant Analysis',
      icon: Icons.eco_outlined,
      status: _aqi?.data != null ? _liveStatus : null,
      child: body,
    );
  }

  Widget _weatherOverview() {
    final w = _weather?.data;
    final Widget body;
    if (_weather == null && _liveLoading) {
      body = const LoadingBox(height: 90);
    } else if (_weather?.error != null) {
      body = ErrorBox(message: _weather!.error!, onRetry: _loadLive);
    } else if (w == null) {
      body = const EmptyBox(message: 'No weather data');
    } else {
      // Same fallbacks as [LiveWeatherBody].
      final t = w.temperature;
      final temperature = (t == null || t.isNaN) ? 0.0 : t;
      final summary = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wb_cloudy_outlined, size: 38, color: AppColors.softMint),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${jsNum(temperature)}°C',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (w.condition != null)
            Text(w.condition!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      ]);
      final metrics = Row(children: [
        Expanded(
            child: MetricText(
                label: 'Humidity',
                value: w.humidity == null ? '—' : '${w.humidity!.toStringAsFixed(0)}%')),
        Expanded(
            child: MetricText(
                label: 'Wind',
                value: w.windSpeed == null ? '—' : w.windSpeed!.toStringAsFixed(1))),
        Expanded(
            child: MetricText(
                label: 'Precipitation',
                value: '${(w.precipitation ?? 0).toStringAsFixed(1)} mm')),
      ]);
      body = LayoutBuilder(builder: (context, c) => c.maxWidth < 520
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              summary,
              const SizedBox(height: 12),
              metrics,
            ])
          : Row(children: [
              summary,
              const SizedBox(width: 24),
              Expanded(child: metrics),
            ]));
    }
    const labels = {
      ViewMode.live: 'Live',
      ViewMode.daily: '24 Hours',
      ViewMode.weekly: 'Weekly',
      ViewMode.monthly: 'Monthly',
    };
    return OverviewCard(
      title: 'Weather',
      icon: Icons.cloud_outlined,
      status: w != null ? _liveStatus : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        body,
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: GlassSegmented<ViewMode>(
            values: ViewMode.values,
            selected: _mode,
            dense: true,
            label: (m) => labels[m]!,
            onChanged: (m) {
              _setMode(m);
              widget.onOpenSection?.call(AnalysisSection.weather);
            },
          ),
        ),
      ]),
    );
  }

  /// Selected-area context (formerly the analysis sidebar).
  Widget _areaContext() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: AppDecorations.card(radius: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on_outlined, color: AppColors.mint, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_placeName ?? 'Selected area',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${_lat.toStringAsFixed(4)}°, ${_lng.toStringAsFixed(4)}° · '
                '${ymd(widget.args.startDate)} – ${ymd(widget.args.endDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ]),
          ),
        ]),
      );

  Widget _dateNav() {
    final live = _mode == ViewMode.live;
    final canPrev = live && _viewDate.isAfter(widget.args.startDate) && !_liveLoading;
    final canNext = live && _viewDate.isBefore(_maxDate) && !_liveLoading;
    final label = switch (_mode) {
      ViewMode.live => DateFormat('MMM dd, yyyy').format(_viewDate),
      ViewMode.daily => 'Last 24 Hours',
      ViewMode.weekly => 'Past 7 Days',
      ViewMode.monthly => 'Past 30 Days',
    };
    Widget arrow(IconData icon, bool enabled, int delta, String tip) => Tooltip(
          message: tip,
          child: Material(
            color: enabled ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
            shape: CircleBorder(
                side: BorderSide(
                    color: enabled
                        ? AppColors.accent.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.12))),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? () => _shiftDate(delta) : null,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon,
                    size: 20,
                    color: enabled ? AppColors.accent : Colors.white.withValues(alpha: 0.3)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppDecorations.card(radius: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        arrow(Icons.chevron_left, canPrev, -1, 'Previous Date'),
        const SizedBox(width: 20),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('VIEWING DATE',
                style: TextStyle(fontSize: 11, letterSpacing: 2, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.softMint)),
            ),
          ]),
        ),
        const SizedBox(width: 20),
        arrow(Icons.chevron_right, canNext, 1, 'Next Date'),
      ]),
    );
  }

  // ---------- Live ----------

  /// Two cards side by side on wide layouts, stacked on phones.
  Widget _pair(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(children: [a, const SizedBox(height: 16), b]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ]),
        );
      });

  List<Widget> _liveContent() {
    if (_liveLoading && _aqi == null) {
      return const [LoadingBox(label: 'Loading dashboard data...', height: 260)];
    }
    final aqiMap = _aqi?.data;
    // Live shows the raw API fields (`aqi`, `pm2_5`, …), like the website.
    final aqi = aqiMap == null ? null : AqiRecord.fromJson(aqiMap);
    final weather = _weather?.data;
    final aqiValue = aqi?.aqi;

    final aqiCard = LiveCard(
      title: 'Air Quality Index',
      onTap: _openAqiDetail,
      child: _liveLoading
          ? const LoadingBox(height: 200)
          : _aqi?.error != null
              ? ErrorBox(message: _aqi!.error!, onRetry: _loadLive)
              : AqiGauge(aqi: (aqiValue == null || aqiValue.isNaN) ? 0 : aqiValue),
    );
    final pollutantCard = LiveCard(
      title: 'Pollutant Levels',
      child: _liveLoading
          ? const LoadingBox(height: 200)
          : aqi == null
              ? const EmptyBox(message: 'Unavailable — AQI request failed')
              : PollutantBarChart(record: aqi),
    );
    final weatherCard = LiveCard(
      title: 'Weather',
      onTap: _openWeatherDetail,
      child: _liveLoading
          ? const LoadingBox(height: 200)
          : _weather?.error != null
              ? ErrorBox(message: _weather!.error!, onRetry: _loadLive)
              : weather == null
                  ? const EmptyBox(message: 'No weather data')
                  : LiveWeatherBody(weather: weather),
    );
    final trendCard = LiveCard(
      title: 'UV, Visibility & Pollutants',
      child: _liveLoading
          ? const LoadingBox(height: 200)
          : (aqi == null || weather == null)
              ? const EmptyBox(message: 'Needs both the AQI and weather responses')
              : LiveTrendChart(
                  points: liveSyntheticTrend(
                    uvIndex: weather.uvIndex,
                    uvIndexMax: weather.uvIndexMax,
                    visibility: weather.visibility,
                    pm25: (aqi.value('pm2_5') ?? 0) != 0 ? aqi.value('pm2_5') : aqi.value('pm25'),
                    pm10: aqi.value('pm10'),
                    no2: aqi.value('no2'),
                  ),
                ),
    );
    final report = AqiReportCard(
        key: const ValueKey('aqi-report'), latitude: _lat, longitude: _lng, date: today());
    return switch (widget.section) {
      AnalysisSection.airQuality => [
          _pair(aqiCard, pollutantCard),
          const SizedBox(height: 16),
          report,
        ],
      AnalysisSection.weather => [_pair(weatherCard, trendCard)],
      AnalysisSection.all || AnalysisSection.overview => [
          _pair(aqiCard, pollutantCard),
          const SizedBox(height: 16),
          _pair(weatherCard, trendCard),
          const SizedBox(height: 16),
          report,
        ],
    };
  }

  // ---------- Historical modes ----------

  List<Widget> _periodContent() {
    final (modeLabel, axis) = switch (_mode) {
      ViewMode.daily => ('Last 24 Hours', TrendAxis.daily),
      ViewMode.weekly => ('Last 7 Days', TrendAxis.weekly),
      _ => ('Last 30 Days', TrendAxis.monthly),
    };
    final weatherCard = WeatherSummaryCard(
      data: _weatherCard?.data,
      error: _weatherCard?.error,
      warning: _weatherWarning,
      loading: _cardsLoading,
      date: _viewDate,
      onTap: _openWeatherDetail,
      onRetry: _loadCards,
    );
    final aqiCard = AqiSummaryCard(
      data: _aqiCard?.data,
      error: _aqiCard?.error,
      loading: _cardsLoading,
      date: _viewDate,
      onTap: _openAqiDetail,
      onRetry: _loadCards,
    );
    final trendCard = AqiTrendCard(
      modeLabel: modeLabel,
      axis: axis,
      points: _trend,
      loading: _chartLoading,
      error: _chartError,
      onRefresh: _loadChart,
    );
    const gap = SizedBox(height: 16);
    return switch (widget.section) {
      AnalysisSection.airQuality => [aqiCard, gap, trendCard],
      AnalysisSection.weather => [weatherCard],
      AnalysisSection.all || AnalysisSection.overview => [
          weatherCard, gap, aqiCard, gap, trendCard],
    };
  }
}
