import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/period_logic.dart';
import '../theme.dart';
import 'common.dart';

/// X-axis settings that differ per historical mode (Dashboard.jsx XAxis).
class TrendAxis {
  const TrendAxis({required this.interval, required this.angled, required this.height});

  /// Recharts `interval`: labels shown every (interval + 1) points.
  final int interval;
  final bool angled;
  final double height;

  static const daily = TrendAxis(interval: 2, angled: false, height: 40);
  static const weekly = TrendAxis(interval: 0, angled: true, height: 70);
  static const monthly = TrendAxis(interval: 2, angled: true, height: 60);
}

/// "AQI Trend" card: header with mode pill and refresh, then the chart,
/// a loading message, an error, or "No chart data available".
class AqiTrendCard extends StatelessWidget {
  const AqiTrendCard({
    super.key,
    required this.modeLabel,
    required this.axis,
    required this.points,
    required this.loading,
    required this.onRefresh,
    this.error,
  });

  final String modeLabel;
  final TrendAxis axis;
  final List<TrendPoint> points;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const SizedBox(
        height: 400,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Please wait, data is loading...',
                style: TextStyle(color: AppColors.textMuted)),
          ]),
        ),
      );
    } else if (error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ErrorBox(message: error!, onRetry: onRefresh),
      );
    } else if (points.isEmpty) {
      body = const SizedBox(
        height: 160,
        child: Center(
          child: Text('No chart data available',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    } else {
      body = SizedBox(height: 400, child: AqiTrendChart(points: points, axis: axis));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('AQI Trend',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
            ),
            child: Text(modeLabel,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh AQI Trend Chart',
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accent.withValues(alpha: 0.12),
              foregroundColor: AppColors.accent,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        body,
      ]),
    );
  }
}

class AqiTrendChart extends StatelessWidget {
  const AqiTrendChart({super.key, required this.points, required this.axis});
  final List<TrendPoint> points;
  final TrendAxis axis;

  static const _ticks = [0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0];
  static const _bands = <(double, double, Color)>[
    (0, 50, Color(0xFF10B981)),
    (50, 100, Color(0xFFF59E0B)),
    (100, 150, Color(0xFFF97316)),
    (150, 200, Color(0xFFEF4444)),
    (200, 300, Color(0xFF8B5CF6)),
    (300, 400, Color(0xFF7F1D1D)),
  ];
  static const _axisColor = Color(0xFF9CA3AF);

  bool _isTick(double v) => _ticks.any((t) => (t - v).abs() < 1e-6);

  @override
  Widget build(BuildContext context) {
    // Domain [0, 400] without allowDataOverflow: higher values extend it.
    final maxY = math.max(400.0, points.map((p) => p.aqi.toDouble()).reduce(math.max));
    final every = axis.interval + 1;
    final gridColor = AppColors.accent.withValues(alpha: 0.2);
    return LineChart(LineChartData(
      minX: 0,
      maxX: math.max(1, points.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
        for (final (y1, y2, c) in _bands)
          HorizontalRangeAnnotation(y1: y1, y2: y2, color: c.withValues(alpha: 0.6)),
      ]),
      gridData: FlGridData(
        drawVerticalLine: true,
        horizontalInterval: 50,
        verticalInterval: every.toDouble(),
        checkToShowHorizontalLine: _isTick,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: gridColor, strokeWidth: 1, dashArray: [3, 3]),
        getDrawingVerticalLine: (_) =>
            FlLine(color: gridColor, strokeWidth: 1, dashArray: [3, 3]),
      ),
      borderData: FlBorderData(
        show: true,
        border: const Border(
          left: BorderSide(color: _axisColor),
          bottom: BorderSide(color: _axisColor),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          axisNameWidget: const Text('AQI', style: TextStyle(color: _axisColor, fontSize: 12)),
          axisNameSize: 18,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: 50,
            getTitlesWidget: (v, meta) => _isTick(v)
                ? Text(v.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 12, color: _axisColor))
                : const SizedBox.shrink(),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: axis.height,
            interval: 1,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (v != i || i < 0 || i >= points.length || i % every != 0) {
                return const SizedBox.shrink();
              }
              final text = Text(points[i].label,
                  style: const TextStyle(fontSize: 11, color: _axisColor));
              if (!axis.angled) {
                return Padding(padding: const EdgeInsets.only(top: 6), child: text);
              }
              return SideTitleWidget(
                meta: meta,
                space: 8,
                angle: -math.pi / 4,
                child: text,
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        getTouchedSpotIndicator: (bar, indexes) => [
          for (final _ in indexes)
            TouchedSpotIndicatorData(
              FlLine(color: AppColors.accent.withValues(alpha: 0.4), strokeWidth: 1),
              FlDotData(
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 6, color: AppColors.accent, strokeWidth: 0),
              ),
            ),
        ],
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xF21A1F3A),
          tooltipBorder: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
          tooltipBorderRadius: BorderRadius.circular(8),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${points[s.x.toInt()].label}\n',
                const TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12),
                children: [
                  TextSpan(
                    text: 'AQI: ${jsNum(points[s.x.toInt()].aqi)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].aqi.toDouble()),
          ],
          color: AppColors.accent,
          barWidth: 2,
          isCurved: true,
          preventCurveOverShooting: true,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) =>
                FlDotCirclePainter(radius: 4, color: AppColors.accent, strokeWidth: 0),
          ),
        ),
      ],
    ));
  }
}
