import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/aqi.dart';
import '../models/period_logic.dart';
import '../models/weather.dart';
import '../theme.dart';

/// Dashboard card: navy gradient, teal border, bold title and a divider.
class LiveCard extends StatelessWidget {
  const LiveCard({
    super.key,
    required this.title,
    required this.child,
    this.onTap,
    this.titleSize = 18,
  });

  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppDecorations.card(),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppDecorations.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 4,
                    height: titleSize + 2,
                    decoration: BoxDecoration(
                      gradient: AppGradients.nature,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: titleSize, fontWeight: FontWeight.w700)),
                  ),
                  if (onTap != null)
                    const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                ]),
                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Series colours taken from the website's Live charts.
class LiveColors {
  static const pm25 = Color(0xFF1E40AF);
  static const pm10 = Color(0xFF10B981);
  static const no2 = Color(0xFF84CC16);
  static const so2 = Color(0xFFF97316);
  static const o3 = Color(0xFF94A3B8);
  static const uv = Color(0xFF3B82F6);
  static const visibility = Color(0xFFF97316);
}

const _axisStyle = TextStyle(fontSize: 12, color: Color(0xB3FFFFFF));

/// Recharts tick step for a fixed `[0, max]` domain with 5 ticks
/// (recharts-scale `getFormatStep`).
double rechartsStep(double max) {
  if (max <= 0) return 1;
  final rough = max / 4;
  final digits = (math.log(rough) / math.ln10).floor() + 1;
  final unit = math.pow(10, digits).toDouble();
  final scale = digits != 1 ? 0.05 : 0.1;
  final ratio = double.parse((rough / unit / scale).toStringAsFixed(9));
  return double.parse((ratio.ceil() * scale * unit).toStringAsFixed(9));
}

String _axisLabel(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

Widget _legend(List<(String, Color)> items, {bool line = false}) => Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, color) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: line ? 14 : 10,
              height: line ? 2 : 10,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.softMint)),
          ]),
      ],
    );

/// Y labels at multiples of [step] plus the domain maximum, as recharts
/// renders a fixed domain whose top is not a step multiple.
FlTitlesData _titles({
  required double maxY,
  required double step,
  required Widget Function(double, TitleMeta) bottom,
}) =>
    FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: step,
          getTitlesWidget: (v, meta) {
            final onStep = (v / step - (v / step).round()).abs() < 1e-6;
            final atTop = (v - maxY).abs() < 1e-6;
            final nearTop = !atTop && maxY - v < step * 0.5;
            if ((!onStep && !atTop) || nearTop) return const SizedBox.shrink();
            return Text(_axisLabel(v), style: _axisStyle);
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 1,
          getTitlesWidget: bottom,
        ),
      ),
    );

FlGridData _dashedGrid(double interval, Color color) => FlGridData(
      drawVerticalLine: true,
      horizontalInterval: interval,
      verticalInterval: 1,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: color, strokeWidth: 0.8, dashArray: [3, 3]),
      getDrawingVerticalLine: (_) =>
          FlLine(color: color, strokeWidth: 0.8, dashArray: [3, 3]),
    );

/// Vertical bar per pollutant (PM2.5, PM10, NO2, SO2, O3), as on the website.
class PollutantBarChart extends StatelessWidget {
  const PollutantBarChart({super.key, required this.record});
  final AqiRecord record;

  static const _items = <(String, String, Color)>[
    ('pm2_5', 'PM2.5', LiveColors.pm25),
    ('pm10', 'PM10', LiveColors.pm10),
    ('no2', 'NO2', LiveColors.no2),
    ('so2', 'SO2', LiveColors.so2),
    ('o3', 'O3', LiveColors.o3),
  ];

  static double _or0(double? v) => (v == null || v.isNaN) ? 0 : v;

  @override
  Widget build(BuildContext context) {
    // Website fallbacks: pm2_5 || pm25 || 0; every other pollutant || 0.
    final values = [
      for (final (k, _, _) in _items)
        k == 'pm2_5'
            ? (_or0(record.value('pm2_5')) != 0
                ? _or0(record.value('pm2_5'))
                : _or0(record.value('pm25')))
            : _or0(record.value(k)),
    ];
    // domain [0, 100] without allowDataOverflow: larger values extend the axis.
    final maxY = math.max(100.0, values.reduce(math.max));
    final step = rechartsStep(maxY);
    return Column(children: [
      _legend([for (final (_, l, c) in _items) (l, c)]),
      const SizedBox(height: 14),
      SizedBox(
        height: 200,
        child: LayoutBuilder(builder: (context, c) {
          final barWidth = (c.maxWidth - 40) / _items.length * 0.8;
          return BarChart(BarChartData(
            minY: 0,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: _dashedGrid(step, Colors.white.withValues(alpha: 0.24)),
            borderData: FlBorderData(show: false),
            titlesData: _titles(
              maxY: maxY,
              step: step,
              bottom: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= _items.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_items[i].$2, style: _axisStyle),
                );
              },
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFFFAFAFA),
                tooltipBorder: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
                tooltipBorderRadius: BorderRadius.circular(8),
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${_items[group.x].$2}\n',
                  const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  children: [
                    TextSpan(
                      text: ' : ${values[group.x].toStringAsFixed(2)} µg/m³',
                      style: const TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < _items.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: _items[i].$3,
                    width: barWidth,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]),
            ],
          ));
        }),
      ),
    ]);
  }
}

/// Cloud with rain strokes, as drawn by the website's forecast row.
class _RainIcon extends StatelessWidget {
  const _RainIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 24,
        height: 24,
        child: Stack(alignment: Alignment.topCenter, children: [
          const Icon(Icons.cloud_outlined, size: 20, color: AppColors.softMint),
          Positioned(
            bottom: 0,
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 1.6,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: AppColors.softMint,
                ),
            ]),
          ),
        ]),
      );
}

/// Weather summary card body: metric grid plus the five-day preview row.
class LiveWeatherBody extends StatelessWidget {
  const LiveWeatherBody({super.key, required this.weather});
  final WeatherSummary weather;

  /// Hardcoded on the website (LiveDashboardCards forecastData); not API data.
  static const _fiveDayPreview = <(String, bool, String)>[
    ('MON', true, '25°'),
    ('TUE', true, '26°'),
    ('WED', true, '27°'),
    ('THU', false, '28°'),
    ('FRI', true, '29°'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget metric(IconData icon, String text) => Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0))),
          ),
        ]);
    final w = weather;
    // temperature || 0 and precipitation || precipitation_mm || 0 are website
    // fallbacks. Humidity and wind have none (the website throws), so a
    // missing value is shown as "—" rather than a made-up number.
    final t = w.temperature;
    final temperature = (t == null || t.isNaN) ? 0.0 : t;
    final humidity = w.humidity == null ? '—' : w.humidity!.toStringAsFixed(2);
    final wind = w.windSpeed == null ? '—' : w.windSpeed!.toStringAsFixed(2);
    final precipitation = w.precipitation ?? 0;
    return Column(children: [
      Row(children: [
        Expanded(child: metric(Icons.wb_sunny_outlined, '${jsNum(temperature)}°C')),
        Expanded(child: metric(Icons.water_drop_outlined, '$humidity%')),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: metric(Icons.air, 'Wind Speed $wind')),
        Expanded(
            child: metric(Icons.cloud_outlined,
                'Precipitation ${precipitation.toStringAsFixed(1)} mm')),
      ]),
      const SizedBox(height: 16),
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
      const SizedBox(height: 16),
      Row(children: [
        for (final (day, rain, temp) in _fiveDayPreview)
          Expanded(
            child: Column(children: [
              rain
                  ? const _RainIcon()
                  : const Icon(Icons.wb_sunny_outlined, size: 22, color: AppColors.softMint),
              const SizedBox(height: 6),
              Text(day, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(temp,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    ]);
  }
}

/// "UV, Visibility & Pollutants": six synthetic points derived from the
/// current values with the website's fixed offsets.
class LiveTrendChart extends StatelessWidget {
  const LiveTrendChart({super.key, required this.points});
  final List<LiveTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final series = <(String, String, Color, int, String, double Function(LiveTrendPoint))>[
      ('UV', 'UV Index', LiveColors.uv, 1, '', (p) => p.uv),
      ('Visibility', 'Visibility', LiveColors.visibility, 1, ' km', (p) => p.visibility),
      ('PM2.5', 'PM2.5', LiveColors.pm25, 2, ' µg/m³', (p) => p.pm25),
      ('PM10', 'PM10', LiveColors.pm10, 2, ' µg/m³', (p) => p.pm10),
      ('NO2', 'NO2', LiveColors.no2, 2, ' µg/m³', (p) => p.no2),
    ];
    var maxY = 0.0;
    for (final s in series) {
      for (final p in points) {
        maxY = math.max(maxY, s.$6(p));
      }
    }
    if (maxY <= 0) maxY = 1;
    final step = rechartsStep(maxY);

    return Column(children: [
      _legend([for (final s in series) (s.$1, s.$3)], line: true),
      const SizedBox(height: 14),
      SizedBox(
        height: 200,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: _dashedGrid(step, AppColors.accent.withValues(alpha: 0.2)),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            maxY: maxY,
            step: step,
            bottom: (v, meta) {
              final i = v.round();
              if (v != i || i < 0 || i >= points.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(points[i].time, style: _axisStyle),
              );
            },
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xF21A1F3A),
              tooltipBorder: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
              tooltipBorderRadius: BorderRadius.circular(8),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (var k = 0; k < spots.length; k++)
                  () {
                    final s = series[spots[k].barIndex];
                    return LineTooltipItem(
                      k == 0 ? '${points[spots[k].x.toInt()].time}\n' : '',
                      const TextStyle(
                          color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12),
                      textAlign: TextAlign.left,
                      children: [
                        TextSpan(
                          text: '${s.$2} : ${spots[k].y.toStringAsFixed(s.$4)}${s.$5}',
                          style: TextStyle(
                              color: s.$3, fontWeight: FontWeight.normal, fontSize: 12),
                        ),
                      ],
                    );
                  }(),
              ],
            ),
          ),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < points.length; i++)
                    FlSpot(i.toDouble(), s.$6(points[i])),
                ],
                color: s.$3,
                barWidth: 2,
                isCurved: true,
                preventCurveOverShooting: true,
                dotData: FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 4,
                    color: s.$3,
                    strokeWidth: 0,
                  ),
                ),
              ),
          ],
        )),
      ),
    ]);
  }
}
