import 'package:climateeye/models/period_logic.dart';
import 'package:climateeye/utils/date_utils.dart';
import 'package:climateeye/widgets/live_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(DateTime d) => d.toIso8601String();

void main() {
  group('aggregateAqi', () {
    test('rounds AQI mean and treats missing pollutants as 0', () {
      final a = aggregateAqi([
        {'aqi': 100, 'pm2_5': 10, 'pm10': 20},
        {'aqi': 103, 'pm2_5': 20},
        {'aqi': null, 'pm2_5': 999},
      ])!;
      expect(a.aqi, 102);
      expect(a.pm25, 15);
      expect(a.pm10, 10);
      expect(a.o3, 0);
    });

    test('returns null without valid AQI', () {
      expect(aggregateAqi([{'aqi': null}]), isNull);
    });
  });

  group('aggregateWeather', () {
    test('feels_like falls back to temperature; condition from last record', () {
      final w = aggregateWeather([
        {'temperature': 30, 'feels_like': 34, 'condition': 'Sunny', 'icon': 'sun'},
        {'temperature': 31, 'condition': '', 'icon': null},
      ])!;
      expect(w.temperature, 31);
      expect(w.feelsLike, 32.5);
      expect(w.condition, 'Unknown');
      expect(w.icon, 'cloud');
    });
  });

  group('PeriodWindows', () {
    final w = PeriodWindows(DateTime(2026, 3, 10, 14, 30));
    test('per-component windows', () {
      expect(w.dailyChart.start, DateTime(2026, 3, 9));
      expect(w.weeklyAqiCard.start, DateTime(2026, 3, 3));
      expect(w.weeklyChart.start, DateTime(2026, 3, 4));
      expect(w.weeklyWeatherDays, hasLength(7));
      expect(w.weeklyWeatherDays.first, DateTime(2026, 3, 10));
      expect(w.monthlyAqiCard.start, DateTime(2026, 2, 8));
      expect(w.monthlyWeatherDays, hasLength(30));
      // March has 31 days → today − 30.
      expect(w.monthlyChart.start, DateTime(2026, 2, 8));
      expect(w.monthlyChart.end, DateTime(2026, 3, 10));
    });
  });

  group('dailyTrend', () {
    final now = DateTime(2026, 3, 10, 12, 0);
    test('24 hourly buckets, empty buckets filled with oldest in-window value', () {
      final pts = dailyTrend([
        {'date': iso(now.subtract(const Duration(hours: 20, minutes: 30))), 'aqi': 80},
        {'date': iso(now.subtract(const Duration(minutes: 10))), 'aqi': 120},
        {'date': iso(now.subtract(const Duration(minutes: 20))), 'aqi': 100},
        {'date': iso(now.subtract(const Duration(hours: 30))), 'aqi': 999},
      ], now);
      expect(pts, hasLength(24));
      expect(pts.last.aqi, 110);
      expect(pts.last.label, '12:00');
      expect(pts.first.label, '13:00');
      expect(pts[3].aqi, 80); // bucket 4 = 24 − floor(20.5)
      expect(pts[0].aqi, 80); // filled
    });

    test('empty input gives no points', () {
      expect(dailyTrend(const [], now), isEmpty);
    });
  });

  group('weeklyTrend / monthlyTrend', () {
    final now = DateTime(2026, 2, 10, 9);
    final recs = [
      {'date': '2026-02-08T10:00:00', 'aqi': 50},
      {'date': '2026-02-08T11:00:00', 'aqi': 61},
      {'date': '2026-02-10T08:00:00', 'aqi': 90},
    ];
    test('weekly: rounded daily means, ascending', () {
      final pts = weeklyTrend(recs);
      expect([for (final p in pts) p.label], ['Feb 08', 'Feb 10']);
      expect([for (final p in pts) p.aqi], [56, 90]);
    });

    test('monthly: one point per day of month, missing days use first mean', () {
      final pts = monthlyTrend(recs, now);
      expect(pts, hasLength(28));
      expect(pts.last.label, 'Feb 10');
      expect(pts.last.aqi, 90);
      expect(pts.first.label, 'Jan 14');
      expect(pts.first.aqi, 56);
      expect(pts[pts.length - 3].aqi, 56); // Feb 08
    });
  });

  group('liveSyntheticTrend', () {
    test('website offsets and floors', () {
      final p = liveSyntheticTrend(
          uvIndex: 0, uvIndexMax: 6, visibility: null, pm25: 4, pm10: 30, no2: 2);
      expect([for (final x in p) x.time], ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00']);
      expect([for (final x in p) x.uv], [0, 0, 4, 6, 5, 0]);
      expect([for (final x in p) x.visibility], [5, 7, 8, 10, 9, 8]);
      expect([for (final x in p) x.pm25], [0, 1, 2, 4, 3, 2]);
      expect([for (final x in p) x.pm10], [25, 27, 28, 30, 29, 28]);
      expect([for (final x in p) x.no2], [0, 0, 1, 2, 1.5, 1]);
    });
  });

  group('hourlyAqiSlots', () {
    test('24 slots ending at current hour', () {
      final now = DateTime(2026, 3, 10, 12, 40);
      final slots = hourlyAqiSlots([
        {'date': '2026-03-10T12:05:00', 'aqi': 70},
        {'date': '2026-03-10T11:15:00', 'aqi': 60},
        {'date': '2026-03-10T11:45:00', 'aqi': 65},
      ], now);
      expect(slots, hasLength(24));
      expect(slots.last.time, DateTime(2026, 3, 10, 12));
      expect(slots[22].aqi, 63);
      expect(slots.first.aqi, isNull);
    });
  });

  group('calendar', () {
    test('weekly drops AQI ≤ 0 and zero temperatures', () {
      final d = weeklyCalendarDay(
        [{'temperature': 0}, {'temperature': 25}, {'temperature': 31}],
        [{'aqi': 0}, {'aqi': 88}],
      );
      expect(d.maxAqi, 88);
      expect(d.tempMin, 25);
      expect(d.tempMax, 31);
    });

    test('3-month restriction', () {
      final now = DateTime(2026, 3, 15);
      expect(calendarMonthAllowed(DateTime(2026, 3), now), isTrue);
      expect(calendarMonthAllowed(DateTime(2026, 1), now), isTrue);
      expect(calendarMonthAllowed(DateTime(2025, 12), now), isFalse);
      expect(calendarMonthAllowed(DateTime(2026, 4), now), isFalse);
    });
  });

  group('dailyAqiRows', () {
    test('groups by day with trend from first to last record', () {
      final rows = dailyAqiRows([
        {'date': '2026-03-09T08:00:00', 'aqi': 100, 'pm2_5': 10.123},
        {'date': '2026-03-09T20:00:00', 'aqi': 120, 'pm2_5': 20.0},
        {'date': '2026-03-10T08:00:00', 'aqi': 90, 'trend': '→', 'trend_percentage': 0},
      ]);
      expect([for (final r in rows) r.label], ['Mar 09', 'Mar 10']);
      expect(rows.first.aqi, 110);
      expect(rows.first.pm25, 15.06);
      expect(rows.first.trend, '↑');
      expect(rows.first.trendPercentage, 20);
      expect(rows.last.trend, '→');
    });
  });

  test('rechartsStep matches recharts nice ticks', () {
    expect(rechartsStep(100), 25);
    expect(rechartsStep(120), 30);
    expect(rechartsStep(400), 100);
    expect(rechartsStep(12), 3);
  });

  test('subDays keeps time of day across month boundary', () {
    expect(subDays(DateTime(2026, 3, 1, 9, 30), 1), DateTime(2026, 2, 28, 9, 30));
    expect(ymd(subDays(DateTime(2026, 1, 1), 1)), '2025-12-31');
  });
}
