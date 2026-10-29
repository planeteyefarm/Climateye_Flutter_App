import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/aqi.dart';
import '../models/period_logic.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import 'common.dart';

/// Runs [tasks] with at most [concurrency] in flight, preserving order.
Future<List<R>> runPooled<R>(List<Future<R> Function()> tasks,
    {int concurrency = 6}) async {
  final results = List<R?>.filled(tasks.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < tasks.length) {
      final i = next++;
      results[i] = await tasks[i]();
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
  return results.cast<R>();
}

Future<List<Map<String, dynamic>>?> _orNull(Future<List<Map<String, dynamic>>> f) async {
  try {
    return await f;
  } catch (_) {
    return null;
  }
}

/// "Last 24 Hours AQI" tiles (HourlyAQICards.jsx).
class HourlyAqiTiles extends StatefulWidget {
  const HourlyAqiTiles({super.key, required this.latitude, required this.longitude});
  final double latitude, longitude;

  @override
  State<HourlyAqiTiles> createState() => _HourlyAqiTilesState();
}

class _HourlyAqiTilesState extends State<HourlyAqiTiles> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<HourSlot> _slots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final today = dateOnly(now);
    final yesterday = dateOnly(currentHour.subtract(const Duration(hours: 24)));
    final lat = widget.latitude, lng = widget.longitude;
    List<Map<String, dynamic>> records;
    try {
      try {
        records = await _api.fetchHourlyAqiRange(lat, lng, yesterday, today);
      } catch (_) {
        final r = await Future.wait([
          _orNull(_api.fetchHourlyAqi(lat, lng, today)),
          _orNull(_api.fetchHourlyAqi(lat, lng, yesterday)),
        ]);
        records = [...?r[0], ...?r[1]];
      }
      if (!mounted) return;
      setState(() {
        _slots = hourlyAqiSlots(records, now);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Last 24 Hours AQI',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Air Quality Index for the previous 24 hours from current time',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 14),
        if (_loading)
          const LoadingBox(height: 160)
        else if (_error != null)
          ErrorBox(message: _error!, onRetry: _load)
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in _slots) _tile(s),
          ]),
      ]),
    );
  }

  Widget _tile(HourSlot s) {
    final cat = s.aqi == null ? null : aqiCategory(s.aqi!.toDouble());
    final color = cat?.color ?? const Color(0xFF6B7280);
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: s.aqi == null ? 0.1 : 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(children: [
        Text(DateFormat('HH:mm').format(s.time),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        if (s.aqi == null)
          const Text('No Data', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
        else ...[
          Text('${s.aqi}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(cat!.label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ]),
    );
  }
}

/// Weather calendar (MonthlyWeatherCalendar.jsx). In weekly mode it shows
/// [weekStart]…[weekEnd]; otherwise the calendar month of [selectedDate],
/// limited to the current month and the two before it.
class WeatherCalendar extends StatefulWidget {
  const WeatherCalendar({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.selectedDate,
    this.weekStart,
    this.weekEnd,
  });

  final double latitude, longitude;
  final DateTime selectedDate;
  final DateTime? weekStart, weekEnd;

  bool get weekly => weekStart != null && weekEnd != null;

  @override
  State<WeatherCalendar> createState() => _WeatherCalendarState();
}

class _WeatherCalendarState extends State<WeatherCalendar> {
  final _api = ApiClient.instance;
  late DateTime _month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
  bool _loading = true;
  String? _error;
  Map<String, CalendarDay> _days = {};
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WeatherCalendar old) {
    super.didUpdateWidget(old);
    final m = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    if (!widget.weekly && m != _month) {
      _month = m;
      _load();
    }
  }

  List<DateTime> get _fetchDays {
    final now = DateTime.now();
    final today = dateOnly(now);
    if (widget.weekly) {
      final s = dateOnly(widget.weekStart!), e = dateOnly(widget.weekEnd!);
      return [
        for (var d = s; !d.isAfter(e); d = DateTime(d.year, d.month, d.day + 1)) d,
      ];
    }
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    final end = monthEnd.isBefore(today) ? monthEnd : today;
    return [
      for (var d = _month; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];
  }

  Future<void> _load() async {
    final token = ++_token;
    final now = DateTime.now();
    final label = DateFormat('MMMM yyyy').format(_month);
    if (!widget.weekly) {
      if (_month.isAfter(dateOnly(now))) {
        setState(() {
          _days = {};
          _loading = false;
          _error = 'No data available for $label (future month).';
        });
        return;
      }
      if (!calendarMonthAllowed(_month, now)) {
        setState(() {
          _days = {};
          _loading = false;
          _error = 'No data available for $label. Only data for the last 3 months is available.';
        });
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final days = _fetchDays;
    final lat = widget.latitude, lng = widget.longitude;
    final weather = runPooled([
      for (final d in days)
        () => _orNull(_api
            .fetchHourlyWeather(lat, lng, d)
            .then((l) => [for (final w in l) w.raw])),
    ]);
    final aqi = runPooled([
      for (final d in days) () => _orNull(_api.fetchHourlyAqi(lat, lng, d)),
    ]);
    final w = await weather, a = await aqi;
    if (!mounted || token != _token) return;
    final result = <String, CalendarDay>{};
    for (var i = 0; i < days.length; i++) {
      result[ymd(days[i])] = widget.weekly
          ? weeklyCalendarDay(w[i], a[i])
          : monthlyCalendarDay(w[i], a[i]);
    }
    setState(() {
      _days = result;
      _loading = false;
      if (result.values.every((d) => !d.hasWeather)) {
        _error = widget.weekly
            ? null
            : 'No weather data available for $label.';
      }
    });
  }

  bool get _canPrev {
    final p = DateTime(_month.year, _month.month - 1);
    return calendarMonthAllowed(p, DateTime.now());
  }

  bool get _canNext {
    final now = DateTime.now();
    return _month.year < now.year || (_month.year == now.year && _month.month < now.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.weekly
        ? 'Last 7 Days (${DateFormat('MMM dd').format(widget.weekStart!)} - '
            '${DateFormat('MMM dd, yyyy').format(widget.weekEnd!)})'
        : DateFormat('MMMM yyyy').format(_month);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (!widget.weekly)
            Tooltip(
              message: _canPrev ? 'Previous Month' : 'Only data for the last 3 months is available',
              child: TextButton.icon(
                onPressed: _canPrev && !_loading ? () => _shiftMonth(-1) : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous Month'),
              ),
            ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (!widget.weekly)
            Tooltip(
              message: _canNext ? 'Next Month' : 'Already at current month',
              child: TextButton(
                onPressed: _canNext && !_loading ? () => _shiftMonth(1) : null,
                child: const Row(children: [Text('Next Month'), Icon(Icons.chevron_right)]),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          const LoadingBox(height: 200, label: 'Loading calendar…')
        else if (_error != null)
          ErrorBox(message: _error!, onRetry: _load)
        else
          _grid(),
      ]),
    );
  }

  Widget _grid() {
    final List<DateTime> days;
    final int lead;
    if (widget.weekly) {
      days = _fetchDays;
      lead = days.first.weekday % 7;
    } else {
      final end = DateTime(_month.year, _month.month + 1, 0);
      days = [for (var i = 1; i <= end.day; i++) DateTime(_month.year, _month.month, i)];
      lead = _month.weekday % 7;
    }
    final cells = <DateTime?>[...List.filled(lead, null), ...days];
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 6 * 6) / 7;
      return Column(children: [
        Row(children: [
          for (final d in weekdays)
            SizedBox(
              width: w + (d == 'Sat' ? 0 : 6),
              child: Text(d,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in cells) SizedBox(width: w, child: d == null ? const SizedBox() : _cell(d, w)),
        ]),
      ]);
    });
  }

  Widget _cell(DateTime d, double w) {
    final info = _days[ymd(d)];
    final aqi = info?.maxAqi;
    final cat = aqi == null ? null : aqiCategory(aqi);
    final isToday = ymd(d) == ymd(DateTime.now());
    final compact = w < 80;
    return Container(
      height: compact ? 92 : 110,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cat == null ? AppColors.background.withValues(alpha: 0.6) : cat.color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isToday ? Colors.white : (cat?.color ?? Colors.white.withValues(alpha: 0.08)),
            width: isToday ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${d.day}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(aqi == null ? 'AQI: -' : 'AQI: ${aqi.round()}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cat?.color ?? const Color(0x999CA3AF))),
        ),
        const Spacer(),
        if (info?.hasWeather == true) ...[
          const Icon(Icons.cloud_outlined, size: 18, color: Color(0xFF9CA3AF)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
                '${info!.tempMax == null ? '' : jsNum(info.tempMax!)}°'
                '/${info.tempMin == null ? '' : jsNum(info.tempMin!)}°',
                style: const TextStyle(fontSize: 11)),
          ),
        ] else
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('no weather data',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ),
      ]),
    );
  }
}
