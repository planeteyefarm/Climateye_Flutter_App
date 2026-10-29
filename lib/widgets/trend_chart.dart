import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/aqi.dart';
import '../theme.dart';

class ChartSeries {
  ChartSeries(this.label, this.color, this.values);
  final String label;
  final Color color;

  /// One value per x index; null = no data for that point.
  final List<double?> values;
}

/// Line/bar chart over categorical x positions. Renders only real values.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.series,
    required this.xLabels,
    this.showAqiBands = false,
    this.bar = false,
    this.height = 220,
    this.labelEvery,
  });

  final List<ChartSeries> series;
  final List<String> xLabels;
  final bool showAqiBands;
  final bool bar;
  final double height;

  /// Show every n-th x label; defaults to about six labels.
  final int? labelEvery;

  bool get _hasData => series.any((s) => s.values.any((v) => v != null));

  double get _maxY {
    var m = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v != null && v > m) m = v;
      }
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  int get _labelStep => labelEvery ?? math.max(1, (xLabels.length / 6).ceil());

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data available for this chart',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final titles = FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          getTitlesWidget: (v, meta) => Text(
            meta.formattedValue,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.round();
            if (v != i || i < 0 || i >= xLabels.length || i % _labelStep != 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(xLabels[i],
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            );
          },
        ),
      ),
    );
    final grid = FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: AppColors.border, strokeWidth: 0.5),
    );
    final maxY = _maxY;

    final chart = bar
        ? BarChart(BarChartData(
            maxY: maxY,
            titlesData: titles,
            gridData: grid,
            borderData: FlBorderData(show: false),
            barGroups: [
              for (var i = 0; i < xLabels.length; i++)
                BarChartGroupData(x: i, barRods: [
                  for (final s in series)
                    if (s.values[i] != null)
                      BarChartRodData(
                        toY: s.values[i]!,
                        color: s.color,
                        width: math.max(2, 120 / (xLabels.length * series.length)),
                        borderRadius: BorderRadius.zero,
                      ),
                ]),
            ],
          ))
        : LineChart(LineChartData(
            minX: 0,
            maxX: math.max(1, xLabels.length - 1).toDouble(),
            minY: 0,
            maxY: maxY,
            titlesData: titles,
            gridData: grid,
            borderData: FlBorderData(show: false),
            rangeAnnotations: showAqiBands ? _aqiBands(maxY) : const RangeAnnotations(),
            lineBarsData: [
              for (final s in series)
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < s.values.length; i++)
                      s.values[i] == null
                          ? FlSpot.nullSpot
                          : FlSpot(i.toDouble(), s.values[i]!),
                  ],
                  color: s.color,
                  barWidth: 2,
                  isCurved: false,
                  dotData: FlDotData(show: xLabels.length <= 31),
                ),
            ],
          ));

    return Column(children: [
      SizedBox(height: height, child: chart),
      if (series.length > 1 || showAqiBands) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final s in series) _legendItem(s.label, s.color),
        ]),
      ],
    ]);
  }

  RangeAnnotations _aqiBands(double maxY) {
    const bounds = [0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 100000.0];
    return RangeAnnotations(horizontalRangeAnnotations: [
      for (var i = 0; i < 6; i++)
        if (bounds[i] < maxY)
          HorizontalRangeAnnotation(
            y1: bounds[i],
            y2: math.min(bounds[i + 1], maxY),
            color: aqiCategory(bounds[i] + 1).color.withValues(alpha: 0.12),
          ),
    ]);
  }

  Widget _legendItem(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

const seriesPalette = <Color>[
  Color(0xFF14B8A6),
  Color(0xFFF97316),
  Color(0xFF3B82F6),
  Color(0xFFEAB308),
  Color(0xFFA855F7),
  Color(0xFFEF4444),
  Color(0xFF22C55E),
  Color(0xFFEC4899),
];
