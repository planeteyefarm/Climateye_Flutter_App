import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/aqi.dart';

/// Semi-circular AQI gauge matching the website: six 30° bands from GOOD
/// (left) to HAZARDOUS (right), outside labels, thin needle, white hub.
class AqiGauge extends StatelessWidget {
  const AqiGauge({super.key, required this.aqi});
  final double aqi;

  @override
  Widget build(BuildContext context) {
    final cat = aqiCategory(aqi);
    return Column(children: [
      SizedBox(
        height: 170,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: aqiGaugeAngle(aqi)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, angle, _) => CustomPaint(painter: _GaugePainter(angle)),
        ),
      ),
      const SizedBox(height: 8),
      Text('${cat.label.toUpperCase()} (${aqi.round()})',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: cat.color)),
    ]);
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.angleDeg);
  final double angleDeg;

  static const _bandValues = [25.0, 75.0, 125.0, 175.0, 250.0, 350.0];

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2 - 70, size.height - 40).clamp(40.0, 95.0);
    final stroke = radius * 0.24;
    final center = Offset(size.width / 2, size.height - 12);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const band = math.pi / 6;

    // Canvas angles run clockwise from +x: π is the left end, 2π the right.
    for (var i = 0; i < 6; i++) {
      final cat = aqiCategory(_bandValues[i]);
      canvas.drawArc(
        rect,
        math.pi + i * band,
        band,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = cat.color,
      );

      final mid = math.pi + (i + 0.5) * band;
      final dir = Offset(math.cos(mid), math.sin(mid));
      final anchor = center + dir * (radius + stroke / 2 + 6);
      final tp = TextPainter(
        text: TextSpan(
          text: cat.label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = dir.dx < -0.3
          ? -tp.width
          : dir.dx > 0.3
              ? 0.0
              : -tp.width / 2;
      tp.paint(canvas, Offset(anchor.dx + dx, anchor.dy - tp.height / 2 - (dir.dy < -0.8 ? 4 : 0)));
    }

    final needleAngle = math.pi + angleDeg * math.pi / 180;
    final tip = center +
        Offset(math.cos(needleAngle), math.sin(needleAngle)) * (radius - stroke / 2);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = const Color(0xFF1E40AF)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF1E40AF),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.angleDeg != angleDeg;
}
