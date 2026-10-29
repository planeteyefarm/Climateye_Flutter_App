import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/aqi.dart';
import '../theme.dart';
import 'live_dashboard.dart';

/// Compact titled glass card used for the analysis overview in the map sheet.
class OverviewCard extends StatelessWidget {
  const OverviewCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.status,
  });

  final String title;
  final IconData icon;
  final String? status;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: AppDecorations.card(radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 17, color: AppColors.mint),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
            if (status != null) ...[
              const SizedBox(width: 8),
              StatusChip(label: status!),
            ],
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Small mint pill with a dot, e.g. "Live".
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.mint.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.mint.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.mint)),
        ]),
      );
}

/// Ring gauge: the arc fills with the gauge angle used by [AqiGauge] and
/// takes the category colour.
class AqiRing extends StatelessWidget {
  const AqiRing({super.key, required this.aqi, this.size = 112});
  final double? aqi;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = aqi;
    final cat = v == null ? null : aqiCategory(v);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v == null ? 0 : aqiGaugeAngle(v) / 180),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, f, _) => CustomPaint(
          painter: _RingPainter(f, cat?.color ?? AppColors.textMuted),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(v == null ? '—' : '${v.round()}',
                  style: TextStyle(
                      fontSize: size * 0.24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.cloudWhite)),
              const Text('AQI', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              if (cat != null)
                Text(cat.label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: cat.color)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.color);
  final double fraction;
  final Color color;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2 - 2);
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = AppColors.white.withValues(alpha: 0.1),
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      _start,
      _sweep * fraction.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}

/// Six pollutant readings from a live AQI record, with the app's units.
class PollutantGrid extends StatelessWidget {
  const PollutantGrid({super.key, required this.record, this.columns = 3});
  final AqiRecord record;
  final int columns;

  static const _items = <(String, String, String, Color)>[
    ('pm2_5', 'PM2.5', 'µg/m³', LiveColors.pm25),
    ('pm10', 'PM10', 'µg/m³', LiveColors.pm10),
    ('no2', 'NO₂', 'µg/m³', LiveColors.no2),
    ('so2', 'SO₂', 'µg/m³', LiveColors.so2),
    ('co', 'CO', 'ppm', Color(0xFF8B5CF6)),
    ('o3', 'O₃', 'µg/m³', LiveColors.o3),
  ];

  double? _value(String key) {
    final v = record.value(key);
    if (key == 'pm2_5' && (v == null || v == 0)) return record.value('pm25') ?? v;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    Widget cell((String, String, String, Color) item) {
      final (key, label, unit, color) = item;
      final v = _value(key);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: v == null || v.isNaN ? '—' : v.toStringAsFixed(v.abs() >= 100 ? 0 : 1),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                TextSpan(
                    text: ' $unit',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ]);
    }

    final rows = <Widget>[];
    for (var i = 0; i < _items.length; i += columns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(Row(children: [
        for (var j = i; j < i + columns; j++)
          Expanded(child: j < _items.length ? cell(_items[j]) : const SizedBox()),
      ]));
    }
    return Column(children: rows);
  }
}

/// Label/value pair for compact metric rows.
class MetricText extends StatelessWidget {
  const MetricText({super.key, required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      );
}
