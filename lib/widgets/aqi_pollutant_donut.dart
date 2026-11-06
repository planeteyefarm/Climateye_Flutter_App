import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/aqi.dart';
import 'home_aqi_dashboard.dart';

/// Professional flat colours: red, orange, amber, teal, muted blue, beige.
const kAqiProfessionalColors = <Color>[
  Color(0xFFEF4444), // red / PM2.5
  Color(0xFFF97316), // orange / PM10
  Color(0xFFF59E0B), // amber / NO₂
  Color(0xFF14B8A6), // teal / SO₂
  Color(0xFF3B82F6), // muted blue / O₃
  Color(0xFFD4C5A9), // beige / CO
];

/// Kept for backwards compatibility with tests and callers.
const kAqiPastelColors = kAqiProfessionalColors;

Color flatColorForPollutant(String key) {
  return switch (key) {
    'pm2_5' => const Color(0xFFEF4444),
    'pm10' => const Color(0xFFF97316),
    'no2' => const Color(0xFFF59E0B),
    'so2' => const Color(0xFF14B8A6),
    'o3' => const Color(0xFF3B82F6),
    'co' => const Color(0xFFD4C5A9),
    _ => const Color(0xFF3B82F6),
  };
}

/// Clean flat 2D donut chart; shares from real `/aqi` magnitudes only.
class AqiPollutantDonut extends StatelessWidget {
  const AqiPollutantDonut({
    super.key,
    required this.record,
    this.size = 228,
  });

  final AqiRecord record;
  final double size;

  static double? pollutantValue(AqiRecord record, String key) {
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

  static List<({String key, String label, double value, double share})>
      segmentsFor(AqiRecord record) {
    final entries = <({String key, String label, double value})>[];
    for (final (key, label, _) in kHomePollutantFields) {
      final v = pollutantValue(record, key);
      if (v != null && !v.isNaN && v > 0) {
        entries.add((key: key, label: label, value: v));
      }
    }
    final sum = entries.fold<double>(0, (a, e) => a + e.value);
    if (sum <= 0) return const [];
    return [
      for (final e in entries)
        (key: e.key, label: e.label, value: e.value, share: e.value / sum),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final aqi = record.aqi;
    final cat = aqi != null ? aqiCategory(aqi) : null;
    final segments = segmentsFor(record);
    // Diameter of center hole inside flat 2D ring (2 * size * 0.27).
    final hole = size * 0.54;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _Flat2DDonutPainter(segments: segments),
          ),
          Container(
            width: hole,
            height: hole,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hole * 0.08),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AQI',
                      style: TextStyle(
                        fontSize: hole * 0.12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                        letterSpacing: 0.4,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      aqi == null || aqi.isNaN ? '—' : '${aqi.round()}',
                      style: TextStyle(
                        fontSize: hole * 0.38,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (cat != null)
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: hole * 0.13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                          height: 1.15,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reference layout: header + clay donut + glass pollutant list + glass status (Design 3).
class AqiPollutantDistributionPanel extends StatelessWidget {
  const AqiPollutantDistributionPanel({
    super.key,
    required this.record,
    this.compact = false,
    this.showInlineHeader = true,
    this.donutSize,
    this.isSatellite = false,
  });

  final AqiRecord record;
  final bool compact;
  final bool showInlineHeader;
  final double? donutSize;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    final segments = AqiPollutantDonut.segmentsFor(record);
    final shareByKey = {for (final s in segments) s.key: s.share};
    final cat = record.aqi != null ? aqiCategory(record.aqi!) : null;

    final cardBg = isSatellite
        ? const Color(0xFF0F172A).withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.88);
    final cardBorder = isSatellite
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFFCBD5E1);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder, width: 1.1),
        boxShadow: isSatellite
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showInlineHeader) ...[
            _DistributionHeader(compact: compact, isSatellite: isSatellite),
            SizedBox(height: compact ? 10 : 14),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final chartSize = donutSize ?? (compact ? 116.0 : 126.0);
              if (constraints.maxWidth >= 270) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AqiPollutantDonut(record: record, size: chartSize),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(
                      child: _PollutantDetailsCard(
                        record: record,
                        shareByKey: shareByKey,
                        compact: compact,
                        isSatellite: isSatellite,
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Center(child: AqiPollutantDonut(record: record, size: chartSize)),
                  const SizedBox(height: 12),
                  _PollutantDetailsCard(
                    record: record,
                    shareByKey: shareByKey,
                    compact: compact,
                    isSatellite: isSatellite,
                  ),
                ],
              );
            },
          ),
          SizedBox(height: compact ? 10 : 14),
          _GlassStatusFooter(
            message: cat == null
                ? 'Air quality data unavailable.'
                : 'Air quality is ${cat.label.toLowerCase()}.',
            compact: compact,
            isSatellite: isSatellite,
          ),
        ],
      ),
    );
  }
}

class _DistributionHeader extends StatelessWidget {
  const _DistributionHeader({required this.compact, required this.isSatellite});

  final bool compact;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AQI',
          style: TextStyle(
            fontSize: compact ? 22 : 24,
            fontWeight: FontWeight.w800,
            color: isSatellite ? Colors.white : const Color(0xFF0F172A),
            height: 1.05,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Pollutant Distribution',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: isSatellite
                ? Colors.white.withValues(alpha: 0.85)
                : const Color(0xFF475569),
          ),
        ),
      ],
    );
  }
}

class _PollutantDetailsCard extends StatelessWidget {
  const _PollutantDetailsCard({
    required this.record,
    required this.shareByKey,
    required this.compact,
    required this.isSatellite,
  });

  final AqiRecord record;
  final Map<String, double> shareByKey;
  final bool compact;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < kHomePollutantFields.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 3 : 4),
          _PollutantDetailRow(
            color: flatColorForPollutant(kHomePollutantFields[i].$1),
            label: kHomePollutantFields[i].$2,
            value: AqiPollutantDonut.pollutantValue(
                record, kHomePollutantFields[i].$1),
            share: shareByKey[kHomePollutantFields[i].$1],
            compact: compact,
            isSatellite: isSatellite,
          ),
        ],
      ],
    );
  }
}

class _PollutantDetailRow extends StatelessWidget {
  const _PollutantDetailRow({
    required this.color,
    required this.label,
    required this.value,
    required this.share,
    required this.compact,
    required this.isSatellite,
  });

  final Color color;
  final String label;
  final double? value;
  final double? share;
  final bool compact;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    final valueText = value == null || value!.isNaN
        ? '—'
        : value!.abs() >= 100
            ? value!.round().toString()
            : value!.toStringAsFixed(value! == value!.roundToDouble() ? 0 : 1);
    final pctText = share == null ? '—' : '${(share! * 100).round()}%';

    final labelColor = isSatellite
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF1E293B);
    final valColor = isSatellite
        ? Colors.white
        : const Color(0xFF0F172A);
    final pctColor = isSatellite
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF64748B);

    return Row(
      children: [
        Container(
          width: compact ? 13 : 15,
          height: compact ? 13 : 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ),
        Text(
          valueText,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w800,
            color: valColor,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        SizedBox(
          width: compact ? 28 : 32,
          child: Text(
            pctText,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: pctColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassStatusFooter extends StatelessWidget {
  const _GlassStatusFooter({
    required this.message,
    required this.compact,
    required this.isSatellite,
  });

  final String message;
  final bool compact;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    final pillBg = isSatellite
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFF1F5F9).withValues(alpha: 0.9);
    final pillBorder = isSatellite
        ? Colors.white.withValues(alpha: 0.3)
        : const Color(0xFFE2E8F0);
    final textColor = isSatellite
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF0F172A);

    return Container(
      height: compact ? 38 : 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: pillBg,
        border: Border.all(color: pillBorder, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2563EB),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean, professional flat 2D donut chart with subtle segment spacing.
class _Flat2DDonutPainter extends CustomPainter {
  _Flat2DDonutPainter({required this.segments});

  final List<({String key, String label, double value, double share})> segments;

  static const _gapRad = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final outer = size.width * 0.44;
    final inner = size.width * 0.28;
    final mid = (outer + inner) / 2;
    final thickness = outer - inner;

    if (segments.isEmpty) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: mid),
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = const Color(0xFFCBD5E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.butt,
      );
      return;
    }

    var angle = -math.pi / 2;
    final hasMultiple = segments.where((s) => s.share > 0.005).length > 1;
    final gap = hasMultiple ? _gapRad : 0.0;

    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final sweep = s.share * 2 * math.pi;
      final drawSweep = math.max(0.0, sweep - gap);
      final start = angle + gap / 2;

      if (drawSweep > 0.005) {
        final color = flatColorForPollutant(s.key);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: mid),
          start,
          drawSweep,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness
            ..strokeCap = StrokeCap.butt,
        );
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Flat2DDonutPainter old) =>
      old.segments != segments;
}

/// Split status pill matching the reference header.
class AqiStatusBadge extends StatelessWidget {
  const AqiStatusBadge({super.key, required this.aqi, required this.category});
  final double aqi;
  final AqiCategory category;

  @override
  Widget build(BuildContext context) {
    final warm = category.label == 'Poor' ||
        category.label == 'Moderate' ||
        category.label == 'Unhealthy';
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 5, 4, 5),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${aqi.round()}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: warm
                  ? const Color(0xFFFFE0C2).withValues(alpha: 0.9)
                  : category.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              category.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: warm ? const Color(0xFFE67E22) : category.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
