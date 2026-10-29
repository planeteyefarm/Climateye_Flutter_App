import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/aqi.dart';
import 'home_aqi_dashboard.dart';

/// Pastel segment colours from the definitive reference (pink → purple).
const kAqiPastelColors = <Color>[
  Color(0xFFE87385), // pink / PM2.5
  Color(0xFFE8964A), // orange / PM10
  Color(0xFFE0B83A), // yellow / NO₂
  Color(0xFF78C878), // mint / SO₂
  Color(0xFF6AB0D8), // sky / O₃
  Color(0xFFA890D0), // purple / CO
];

/// Volumetric 3D donut; shares from real `/aqi` magnitudes only.
class AqiPollutantDonut extends StatelessWidget {
  const AqiPollutantDonut({
    super.key,
    required this.record,
    this.size = 220,
  });

  final AqiRecord record;

  /// Full widget size (includes margin for external leader labels).
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
    // Must match painter inner radius (size * 0.195) so the readout fills the hole.
    final hole = size * 0.38;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _VolumetricDonutPainter(segments: segments),
          ),
          Container(
            width: hole,
            height: hole,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFCFDFE),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                  spreadRadius: -1,
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hole * 0.12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AQI',
                      style: TextStyle(
                        fontSize: hole * 0.11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.4,
                        height: 1,
                      ),
                    ),
                    Text(
                      aqi == null || aqi.isNaN ? '—' : '${aqi.round()}',
                      style: TextStyle(
                        fontSize: hole * 0.36,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E3A5F),
                        height: 1.0,
                      ),
                    ),
                    if (cat != null)
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: hole * 0.13,
                          fontWeight: FontWeight.w700,
                          color: cat.label == 'Poor' ||
                                  cat.label == 'Unhealthy' ||
                                  cat.label == 'Severe'
                              ? const Color(0xFFE67E22)
                              : const Color(0xFF64748B),
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

/// Compact reference card: header + donut + list + footer leaves.
class AqiPollutantDistributionPanel extends StatelessWidget {
  const AqiPollutantDistributionPanel({
    super.key,
    required this.record,
    this.compact = false,
    this.showInlineHeader = true,
  });

  final AqiRecord record;
  final bool compact;
  final bool showInlineHeader;

  @override
  Widget build(BuildContext context) {
    final segments = AqiPollutantDonut.segmentsFor(record);
    final shareByKey = {for (final s in segments) s.key: s.share};
    final donutSize = compact ? 200.0 : 236.0;
    final cat = record.aqi != null ? aqiCategory(record.aqi!) : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.none,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 18,
              compact ? 10 : 12,
              compact ? 14 : 18,
              compact ? 10 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showInlineHeader) ...[
                  _DistributionHeader(
                    aqi: record.aqi,
                    category: cat,
                    compact: compact,
                  ),
                  SizedBox(height: compact ? 6 : 8),
                ],
                Center(
                  child: AqiPollutantDonut(record: record, size: donutSize),
                ),
                SizedBox(height: compact ? 8 : 10),
                _PollutantDetailsCard(
                  record: record,
                  shareByKey: shareByKey,
                  compact: compact,
                ),
                SizedBox(height: compact ? 10 : 12),
                // Footer + leaf sit in one composition (leaf tucked at corner).
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _AirQualityFooter(
                      message: cat == null
                          ? 'Air quality data unavailable.'
                          : 'Air quality is ${cat.label.toLowerCase()}.',
                    ),
                    Positioned(
                      right: -2,
                      bottom: -6,
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size(compact ? 58 : 70, compact ? 52 : 62),
                          painter: _LeafClusterPainter(opacity: 0.55),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionHeader extends StatelessWidget {
  const _DistributionHeader({
    required this.aqi,
    required this.category,
    required this.compact,
  });

  final double? aqi;
  final AqiCategory? category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AQI',
                style: TextStyle(
                  fontSize: compact ? 22 : 24,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E3A5F),
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Pollutant Distribution',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
        if (aqi != null && category != null)
          AqiStatusBadge(aqi: aqi!, category: category!),
      ],
    );
  }
}

class _PollutantDetailsCard extends StatelessWidget {
  const _PollutantDetailsCard({
    required this.record,
    required this.shareByKey,
    required this.compact,
  });

  final AqiRecord record;
  final Map<String, double> shareByKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < kHomePollutantFields.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
            _PollutantDetailRow(
              color: kAqiPastelColors[i % kAqiPastelColors.length],
              label: kHomePollutantFields[i].$2,
              value: AqiPollutantDonut.pollutantValue(
                  record, kHomePollutantFields[i].$1),
              share: shareByKey[kHomePollutantFields[i].$1],
              compact: compact,
            ),
          ],
        ],
      ),
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
  });

  final Color color;
  final String label;
  final double? value;
  final double? share;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valueText = value == null || value!.isNaN
        ? '—'
        : value!.abs() >= 100
            ? value!.round().toString()
            : value!.toStringAsFixed(value! == value!.roundToDouble() ? 0 : 1);
    final pctText = share == null ? '—' : '${(share! * 100).round()}%';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 6 : 7.5,
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 22 : 24,
            height: compact ? 22 : 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [
                  Color.lerp(color, Colors.white, 0.4)!,
                  color,
                  Color.lerp(color, const Color(0xFF475569), 0.12)!,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Icon(
              Icons.eco_rounded,
              size: compact ? 11 : 12,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E3A5F),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E3A5F),
              ),
            ),
          ),
          SizedBox(
            width: compact ? 40 : 44,
            child: Text(
              pctText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AirQualityFooter extends StatelessWidget {
  const _AirQualityFooter({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD4EDE6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            child: const Icon(Icons.eco, size: 14, color: Color(0xFF14B8A6)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
          // Space reserved so text doesn't collide with the leaf accent.
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}

/// Matte-satin volumetric ring with upright / leader labels (no curved glyphs).
class _VolumetricDonutPainter extends CustomPainter {
  _VolumetricDonutPainter({required this.segments});

  final List<({String key, String label, double value, double share})> segments;

  /// White groove between segments (radians).
  static const _gapRad = 0.055;

  /// Omit chart labels below this share (still shown in the list).
  static const _omitBelowShare = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // Ring fits in ~78% of canvas; outer margin holds leader labels.
    // Thickness ~22% of size → raised clay-like ring matching the reference.
    final outer = size.width * 0.40;
    final inner = size.width * 0.195;
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
          ..strokeWidth = thickness,
      );
      return;
    }

    // Soft contact shadow under the whole ring (no harsh glow).
    canvas.drawArc(
      Rect.fromCircle(center: c + const Offset(0, 5), radius: mid),
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 0.92
        ..color = const Color(0xFF64748B).withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Pass 1: extrusion + body for every segment.
    var angle = -math.pi / 2;
    final starts = <double>[];
    final sweeps = <double>[];
    for (var i = 0; i < segments.length; i++) {
      final share = segments[i].share;
      final sweep = share * 2 * math.pi;
      final drawSweep = math.max(0.0, sweep - _gapRad);
      final start = angle + _gapRad / 2;
      starts.add(start);
      sweeps.add(drawSweep);
      if (drawSweep > 0.01) {
        _paintSegment(
          canvas,
          c,
          inner: inner,
          outer: outer,
          start: start,
          sweep: drawSweep,
          color: kAqiPastelColors[i % kAqiPastelColors.length],
        );
      }
      angle += sweep;
    }

    // Pass 2: percentage labels — upright only; leader if they won't fit.
    for (var i = 0; i < segments.length; i++) {
      final share = segments[i].share;
      final start = starts[i];
      final drawSweep = sweeps[i];
      if (drawSweep < 0.01 || share < _omitBelowShare) continue;

      final text = '${(share * 100).round()}%';
      final midA = start + drawSweep / 2;
      final arcLen = mid * drawSweep;
      final fontOn = size.width * 0.042;
      final approxTextW = text.length * fontOn * 0.58;

      if (arcLen >= approxTextW * 1.15) {
        _paintUprightLabel(
          canvas,
          Offset(
            c.dx + math.cos(midA) * mid,
            c.dy + math.sin(midA) * mid,
          ),
          text: text,
          fontSize: fontOn,
          onRing: true,
        );
      } else {
        final ringPt = Offset(
          c.dx + math.cos(midA) * (outer + 2),
          c.dy + math.sin(midA) * (outer + 2),
        );
        final labelR = outer + size.width * 0.085;
        final labelPt = Offset(
          c.dx + math.cos(midA) * labelR,
          c.dy + math.sin(midA) * labelR,
        );
        _paintLeader(canvas, ringPt, labelPt);
        _paintUprightLabel(
          canvas,
          labelPt,
          text: text,
          fontSize: size.width * 0.034,
          onRing: false,
        );
      }
    }
  }

  Path _sectorPath(
    Offset c, {
    required double inner,
    required double outer,
    required double start,
    required double sweep,
  }) {
    final path = Path()
      ..moveTo(
        c.dx + math.cos(start) * outer,
        c.dy + math.sin(start) * outer,
      )
      ..arcTo(
        Rect.fromCircle(center: c, radius: outer),
        start,
        sweep,
        false,
      )
      ..lineTo(
        c.dx + math.cos(start + sweep) * inner,
        c.dy + math.sin(start + sweep) * inner,
      )
      ..arcTo(
        Rect.fromCircle(center: c, radius: inner),
        start + sweep,
        -sweep,
        false,
      )
      ..close();
    return path;
  }

  void _paintSegment(
    Canvas canvas,
    Offset c, {
    required double inner,
    required double outer,
    required double start,
    required double sweep,
    required Color color,
  }) {
    final mid = (outer + inner) / 2;
    final thickness = outer - inner;
    final path = _sectorPath(
      c,
      inner: inner,
      outer: outer,
      start: start,
      sweep: sweep,
    );

    // Extrusion (physical thickness) — layered offsets for clay depth.
    for (final o in const [
      Offset(3.4, 5.2),
      Offset(2.2, 3.4),
      Offset(1.1, 1.7),
    ]) {
      canvas.drawPath(
        path.shift(o),
        Paint()
          ..color = Color.lerp(color, const Color(0xFF1E293B), 0.48)!
              .withValues(alpha: 0.32 + o.dy * 0.025),
      );
    }

    // Rounded end caps via thick stroke underneath the wedge (soft clay tips).
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: mid),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Matte-satin top face over the wedge (subtle radial, not glass glow).
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-outer * 0.28, -outer * 0.4),
          outer * 1.55,
          [
            Color.lerp(color, Colors.white, 0.26)!,
            color,
            Color.lerp(color, const Color(0xFF475569), 0.16)!,
          ],
          const [0.0, 0.48, 1.0],
        ),
    );

    // Soft outer rim highlight (satin edge only).
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: outer - 1.4),
      start + 0.02,
      math.max(0.0, sweep - 0.04),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.42),
    );

    // Inner rim shade.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: inner + 1.2),
      start + 0.02,
      math.max(0.0, sweep - 0.04),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF334155).withValues(alpha: 0.16),
    );

    // Tiny specular along the crown — restrained.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: mid),
      start + sweep * 0.12,
      sweep * 0.28,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 0.16
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.2),
    );
  }

  void _paintLeader(Canvas canvas, Offset from, Offset to) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = const Color(0xFF94A3B8).withValues(alpha: 0.55)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      from,
      1.6,
      Paint()..color = const Color(0xFF94A3B8).withValues(alpha: 0.7),
    );
  }

  void _paintUprightLabel(
    Canvas canvas,
    Offset center, {
    required String text,
    required double fontSize,
    required bool onRing,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: onRing ? Colors.white : const Color(0xFF475569),
          shadows: onRing
              ? const [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 2,
                    offset: Offset(0, 0.5),
                  ),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _VolumetricDonutPainter old) =>
      old.segments != segments;
}

/// Delicate botanical accent for the footer corner.
class _LeafClusterPainter extends CustomPainter {
  _LeafClusterPainter({required this.opacity});
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()
      ..color = const Color(0xFF86EFAC).withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    final b = Paint()
      ..color = const Color(0xFF4ADE80).withValues(alpha: opacity * 0.7)
      ..style = PaintingStyle.fill;
    final stem = Paint()
      ..color = const Color(0xFF22C55E).withValues(alpha: opacity * 0.4)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final base = Offset(size.width * 0.92, size.height * 0.88);
    canvas.drawLine(base, Offset(size.width * 0.35, size.height * 0.2), stem);
    canvas.drawLine(base, Offset(size.width * 0.18, size.height * 0.55), stem);

    void leaf(Offset tip, double len, double bulge, double angle, Paint p) {
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(len * 0.5, -bulge, len, 0)
        ..quadraticBezierTo(len * 0.5, bulge, 0, 0)
        ..close();
      canvas.drawPath(path, p);
      canvas.restore();
    }

    leaf(Offset(size.width * 0.48, size.height * 0.28), size.width * 0.38,
        size.height * 0.1, -0.9, a);
    leaf(Offset(size.width * 0.3, size.height * 0.52), size.width * 0.32,
        size.height * 0.085, -0.45, b);
    leaf(Offset(size.width * 0.55, size.height * 0.6), size.width * 0.28,
        size.height * 0.075, -1.2, a);
  }

  @override
  bool shouldRepaint(covariant _LeafClusterPainter old) =>
      old.opacity != opacity;
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
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${aqi.round()}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: warm
                  ? const Color(0xFFFFE0C2)
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
