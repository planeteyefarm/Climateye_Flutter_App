import 'package:intl/intl.dart';

import '../utils/date_utils.dart';
import 'json_utils.dart';

/// Website helpers ported from Dashboard.jsx, AQIDetailPage.jsx,
/// HourlyAQICards.jsx and MonthlyWeatherCalendar.jsx. All functions are
/// pure so they can be unit tested; records are the raw API maps.

/// JavaScript `a || b` for numbers: null, 0 and NaN fall through.
double? _or(double? a) => (a == null || a == 0 || a.isNaN) ? null : a;

double? _num(Map<String, dynamic> r, String key) => toDouble(r[key]);

DateTime? _date(Map<String, dynamic> r) => parseApiDate(r['date']);

/// date-fns `subDays`: calendar days, keeping the time of day.
DateTime subDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day - n, d.hour, d.minute, d.second, d.millisecond);

/// Number as JavaScript prints it: 30.0 → "30", 29.4 → "29.4".
String jsNum(num v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

// ---------------------------------------------------------------------------
// aggregateHourlyData (Dashboard.jsx)

class AqiAggregate {
  AqiAggregate({
    required this.aqi,
    required this.pm25,
    required this.pm10,
    required this.co,
    required this.so2,
    required this.no2,
    required this.o3,
  });
  final int aqi;
  final double pm25, pm10, co, so2, no2, o3;
}

AqiAggregate? aggregateAqi(List<Map<String, dynamic>> records) {
  final valid = records.where((r) => _num(r, 'aqi') != null).toList();
  if (valid.isEmpty) return null;
  final n = valid.length;
  double mean(String k) => valid.fold(0.0, (s, r) => s + (_or(_num(r, k)) ?? 0)) / n;
  return AqiAggregate(
    aqi: (valid.fold(0.0, (s, r) => s + _num(r, 'aqi')!) / n).round(),
    pm25: mean('pm2_5'),
    pm10: mean('pm10'),
    co: mean('co'),
    so2: mean('so2'),
    no2: mean('no2'),
    o3: mean('o3'),
  );
}

class WeatherAggregate {
  WeatherAggregate({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.uvIndex,
    required this.condition,
    required this.icon,
  });
  final int temperature;
  final double feelsLike, humidity, windSpeed, uvIndex;
  final String condition, icon;
}

WeatherAggregate? aggregateWeather(List<Map<String, dynamic>> records) {
  final valid = records.where((r) => _num(r, 'temperature') != null).toList();
  if (valid.isEmpty) return null;
  final n = valid.length;
  double mean(String k) => valid.fold(0.0, (s, r) => s + (_or(_num(r, k)) ?? 0)) / n;
  final last = valid.last;
  final condition = toStr(last['condition']);
  final icon = toStr(last['icon']);
  return WeatherAggregate(
    temperature: (valid.fold(0.0, (s, r) => s + _num(r, 'temperature')!) / n).round(),
    feelsLike: valid.fold(
            0.0, (s, r) => s + (_or(_num(r, 'feels_like')) ?? _num(r, 'temperature')!)) /
        n,
    humidity: mean('humidity'),
    windSpeed: mean('wind_speed'),
    uvIndex: mean('uv_index'),
    condition: (condition == null || condition.isEmpty) ? 'Unknown' : condition,
    icon: (icon == null || icon.isEmpty) ? 'cloud' : icon,
  );
}

// ---------------------------------------------------------------------------
// Request windows per component (Dashboard.jsx, WeatherSection.jsx).

class DateWindow {
  const DateWindow(this.start, this.end);
  final DateTime start, end;
}

class PeriodWindows {
  PeriodWindows(this.now);
  final DateTime now;

  DateTime get today => dateOnly(now);

  /// Last 24 Hrs cards: today's calendar day.
  DateTime get dailyCardsDate => today;

  /// Last 24 Hrs chart: `now − 24 h` … today.
  DateWindow get dailyChart =>
      DateWindow(dateOnly(now.subtract(const Duration(hours: 24))), today);

  /// Weekly AQI card: today − 7 … today (8 dates).
  DateWindow get weeklyAqiCard => DateWindow(dateOnly(subDays(now, 7)), today);

  /// Weekly weather card: today, today − 1, … today − 6.
  List<DateTime> get weeklyWeatherDays =>
      [for (var i = 0; i < 7; i++) dateOnly(subDays(now, i))];

  /// Weekly chart: today − 6 … today (7 dates).
  DateWindow get weeklyChart => DateWindow(dateOnly(subDays(now, 6)), today);

  /// Monthly AQI card: today − 30 … today (31 dates).
  DateWindow get monthlyAqiCard => DateWindow(dateOnly(subDays(now, 30)), today);

  /// Monthly weather card: today, … today − 29.
  List<DateTime> get monthlyWeatherDays =>
      [for (var i = 0; i < 30; i++) dateOnly(subDays(now, i))];

  /// Monthly chart: today − (D − 1) … today, D = days in current month.
  DateWindow get monthlyChart =>
      DateWindow(dateOnly(subDays(now, daysInMonth(now) - 1)), today);
}

// ---------------------------------------------------------------------------
// AQI Trend chart data (fetchAQIChartData).

class TrendPoint {
  const TrendPoint(this.label, this.aqi);
  final String label;
  final num aqi;
}

typedef _Rec = ({DateTime t, double aqi});

List<_Rec> _withAqi(List<Map<String, dynamic>> records) => [
      for (final r in records)
        if (_num(r, 'aqi') != null && _date(r) != null) (t: _date(r)!, aqi: _num(r, 'aqi')!),
    ];

/// Rolling 24-hour window in 24 hourly buckets.
List<TrendPoint> dailyTrend(List<Map<String, dynamic>> records, DateTime now) {
  final from = now.subtract(const Duration(hours: 24));
  final inWindow = _withAqi(records)
      .where((r) => !r.t.isBefore(from) && !r.t.isAfter(now))
      .toList()
    ..sort((a, b) => a.t.compareTo(b.t));
  final fmt = DateFormat('HH:mm');
  String label(int hour) => fmt.format(now.subtract(Duration(hours: 24 - hour)));

  if (inWindow.isNotEmpty) {
    final buckets = <int, List<double>>{};
    for (final r in inWindow) {
      final pos = 24 - (now.difference(r.t).inMilliseconds / 3600000).floor();
      if (pos >= 1 && pos <= 24) buckets.putIfAbsent(pos, () => []).add(r.aqi);
    }
    final fill = _or(inWindow.first.aqi) ?? 0;
    return [
      for (var h = 1; h <= 24; h++)
        TrendPoint(
          label(h),
          buckets[h] == null
              ? fill
              : (buckets[h]!.reduce((a, b) => a + b) / buckets[h]!.length).round(),
        ),
    ];
  }
  if (records.isEmpty) return const [];
  double? at(int i) => i < records.length ? _or(_num(records[i], 'aqi')) : null;
  return [
    for (var h = 1; h <= 24; h++) TrendPoint(label(h), at(h - 1) ?? at(0) ?? 0),
  ];
}

Map<String, ({DateTime first, List<double> aqis})> _groupByDay(
    List<Map<String, dynamic>> records) {
  final groups = <String, ({DateTime first, List<double> aqis})>{};
  for (final r in _withAqi(records)) {
    final key = ymd(r.t);
    groups.putIfAbsent(key, () => (first: r.t, aqis: <double>[])).aqis.add(r.aqi);
  }
  return groups;
}

int _meanRound(List<double> v) => (v.reduce((a, b) => a + b) / v.length).round();

/// Daily means, ascending; days without data are omitted.
List<TrendPoint> weeklyTrend(List<Map<String, dynamic>> records) {
  final groups = _groupByDay(records);
  final keys = groups.keys.toList()..sort();
  final fmt = DateFormat('MMM dd');
  return [
    for (final k in keys) TrendPoint(fmt.format(groups[k]!.first), _meanRound(groups[k]!.aqis)),
  ];
}

/// Daily means for every day of the current month's length. Missing days
/// (and days whose mean is 0) take the first available day's mean.
List<TrendPoint> monthlyTrend(List<Map<String, dynamic>> records, DateTime now) {
  final groups = _groupByDay(records);
  final keys = groups.keys.toList()..sort();
  final fmt = DateFormat('MMM dd');
  final data = [
    for (final k in keys) (key: k, label: fmt.format(groups[k]!.first), aqi: _meanRound(groups[k]!.aqis)),
  ];
  if (data.isEmpty) return const [];
  final d = daysInMonth(now);
  if (data.length >= d) return [for (final p in data) TrendPoint(p.label, p.aqi)];
  final byKey = {for (final p in data) p.key: p.aqi};
  return [
    for (var i = 0; i < d; i++)
      () {
        final day = subDays(now, d - i - 1);
        final v = byKey[ymd(day)];
        return TrendPoint(fmt.format(day), (v == null || v == 0) ? data.first.aqi : v);
      }(),
  ];
}

// ---------------------------------------------------------------------------
// Live "UV, Visibility & Pollutants" synthetic series (LiveDashboardCards.jsx).

class LiveTrendPoint {
  const LiveTrendPoint(this.time, this.uv, this.visibility, this.pm25, this.pm10, this.no2);
  final String time;
  final double uv, visibility, pm25, pm10, no2;
}

List<LiveTrendPoint> liveSyntheticTrend({
  required double? uvIndex,
  required double? uvIndexMax,
  required double? visibility,
  required double? pm25,
  required double? pm10,
  required double? no2,
}) {
  final uv = _or(uvIndex) ?? _or(uvIndexMax) ?? 0;
  final vis = _or(visibility) ?? 10;
  final p25 = pm25 ?? 0, p10 = pm10 ?? 0, n2 = no2 ?? 0;
  double z(double v) => v < 0 ? 0 : v;
  double v5(double v) => v < 5 ? 5 : v;
  LiveTrendPoint p(String t, double u, double visOff, double pOff, double nOff) =>
      LiveTrendPoint(t, u, v5(vis - visOff), z(p25 - pOff), z(p10 - pOff), z(n2 - nOff));
  return [
    p('00:00', 0, 5, 5, 3),
    p('04:00', 0, 3, 3, 2),
    p('08:00', z(uv - 2), 2, 2, 1),
    LiveTrendPoint('12:00', uv, vis, p25, p10, n2),
    p('16:00', z(uv - 1), 1, 1, 0.5),
    p('20:00', 0, 2, 2, 1),
  ];
}

// ---------------------------------------------------------------------------
// HourlyAQICards.jsx: 24 slots ending at the current hour.

class HourSlot {
  HourSlot(this.time, this.aqi);
  final DateTime time;
  final int? aqi;
}

List<HourSlot> hourlyAqiSlots(List<Map<String, dynamic>> records, DateTime now) {
  final currentHour = DateTime(now.year, now.month, now.day, now.hour);
  final from = currentHour.subtract(const Duration(hours: 24));
  final slots = [
    for (var i = 0; i < 24; i++) currentHour.subtract(Duration(hours: 23 - i)),
  ];
  final perSlot = List.generate(24, (_) => <double>[]);
  for (final r in _withAqi(records)) {
    if (r.t.isBefore(from) || r.t.isAfter(currentHour)) continue;
    final hour = DateTime(r.t.year, r.t.month, r.t.day, r.t.hour);
    final i = slots.indexWhere((s) => (hour.difference(s).inMilliseconds).abs() < 3600000);
    if (i >= 0) perSlot[i].add(r.aqi);
  }
  return [
    for (var i = 0; i < 24; i++)
      HourSlot(slots[i], perSlot[i].isEmpty ? null : _meanRound(perSlot[i])),
  ];
}

// ---------------------------------------------------------------------------
// MonthlyWeatherCalendar.jsx day cells.

class CalendarDay {
  CalendarDay({this.maxAqi, this.tempMax, this.tempMin, this.hasWeather = false});
  final double? maxAqi;
  final double? tempMax, tempMin;
  final bool hasWeather;
}

/// Monthly mode: max AQI over non-null values, max/min over non-null temps.
CalendarDay monthlyCalendarDay(
    List<Map<String, dynamic>>? weather, List<Map<String, dynamic>>? aqi) {
  double? maxAqi;
  for (final r in aqi ?? const <Map<String, dynamic>>[]) {
    final v = _num(r, 'aqi');
    if (v != null && (maxAqi == null || v > maxAqi)) maxAqi = v;
  }
  if (weather == null || weather.isEmpty) return CalendarDay(maxAqi: maxAqi);
  final temps = [for (final r in weather) ?_num(r, 'temperature')];
  return CalendarDay(
    maxAqi: maxAqi,
    hasWeather: true,
    tempMax: temps.isEmpty ? null : temps.reduce((a, b) => a > b ? a : b),
    tempMin: temps.isEmpty ? null : temps.reduce((a, b) => a < b ? a : b),
  );
}

/// Weekly mode: AQI values ≤ 0 dropped; temperatures of 0/missing dropped.
CalendarDay weeklyCalendarDay(
    List<Map<String, dynamic>>? weather, List<Map<String, dynamic>>? aqi) {
  final aqis = [for (final r in aqi ?? const <Map<String, dynamic>>[]) _or(_num(r, 'aqi')) ?? 0]
      .where((v) => v > 0)
      .toList();
  final maxAqi = aqis.isEmpty ? null : aqis.reduce((a, b) => a > b ? a : b);
  if (weather == null || weather.isEmpty) return CalendarDay(maxAqi: maxAqi);
  final temps = [for (final r in weather) ?_or(_num(r, 'temperature'))];
  return CalendarDay(
    maxAqi: maxAqi,
    hasWeather: true,
    tempMax: temps.isEmpty ? null : temps.reduce((a, b) => a > b ? a : b),
    tempMin: temps.isEmpty ? null : temps.reduce((a, b) => a < b ? a : b),
  );
}

/// Months the weather calendar may show: current month and the two before.
bool calendarMonthAllowed(DateTime month, DateTime now) {
  final diff = (month.year - now.year) * 12 + (month.month - now.month);
  return diff >= -2 && diff <= 0;
}

// ---------------------------------------------------------------------------
// AQIDetailPage.jsx weekly/monthly daily rows.

class DailyAqiRow {
  DailyAqiRow({
    required this.label,
    required this.latest,
    required this.aqi,
    this.pm25,
    this.pm10,
    this.co,
    this.no2,
    this.so2,
    this.o3,
    this.trend,
    this.trendPercentage,
  });
  final String label;
  final DateTime latest;
  final int aqi;
  final double? pm25, pm10, co, no2, so2, o3;
  final String? trend;
  final double? trendPercentage;
}

double _round2(double v) => (v * 100).round() / 100;

List<DailyAqiRow> dailyAqiRows(List<Map<String, dynamic>> records) {
  final fmt = DateFormat('MMM dd');
  final groups = <String, List<(DateTime, Map<String, dynamic>)>>{};
  for (final r in records) {
    final t = _date(r);
    if (t == null) continue;
    groups.putIfAbsent(fmt.format(t), () => []).add((t, r));
  }
  final rows = <DailyAqiRow>[];
  groups.forEach((label, recs) {
    recs.sort((a, b) => b.$1.compareTo(a.$1));
    final valid = recs.where((e) => _num(e.$2, 'aqi') != null).toList();
    if (valid.isEmpty) return;
    double? mean(String k) {
      final v = [for (final e in valid) ?_num(e.$2, k)];
      if (v.isEmpty) return null;
      final m = v.reduce((a, b) => a + b) / v.length;
      return m == 0 ? null : _round2(m);
    }

    String? trend;
    double? pct;
    if (valid.length >= 2) {
      final asc = [...valid]..sort((a, b) => a.$1.compareTo(b.$1));
      final first = _num(asc.first.$2, 'aqi')!, last = _num(asc.last.$2, 'aqi')!;
      final diff = last - first;
      trend = diff > 0 ? '↑' : (diff < 0 ? '↓' : '→');
      pct = ((first > 0 ? diff / first * 100 : 0.0).abs() * 10).round() / 10;
    } else {
      trend = toStr(valid.first.$2['trend']);
      pct = _num(valid.first.$2, 'trend_percentage');
    }
    final aqiMean =
        valid.fold(0.0, (s, e) => s + _num(e.$2, 'aqi')!) / valid.length;
    rows.add(DailyAqiRow(
      label: label,
      latest: recs.first.$1,
      aqi: aqiMean.round(),
      pm25: mean('pm2_5'),
      pm10: mean('pm10'),
      co: mean('co'),
      no2: mean('no2'),
      so2: mean('so2'),
      o3: mean('o3'),
      trend: trend,
      trendPercentage: pct,
    ));
  });
  rows.sort((a, b) => a.latest.compareTo(b.latest));
  return rows;
}
