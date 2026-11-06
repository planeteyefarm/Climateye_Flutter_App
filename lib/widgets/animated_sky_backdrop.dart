import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Animated Sky backdrop for Pollutant Distribution — photorealistic base with
/// independently animated cloud, sun, foliage-sway, and floating-leaf layers.
class AnimatedSkyBackdrop extends StatefulWidget {
  const AnimatedSkyBackdrop({super.key});

  /// Primary photorealistic landscape (sky, clouds, mountains, canopy).
  static const skyAsset = 'assets/images/aqi_pollutant_sky_bg.jpg';

  @override
  State<AnimatedSkyBackdrop> createState() => _AnimatedSkyBackdropState();
}

class _AnimatedSkyBackdropState extends State<AnimatedSkyBackdrop>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clouds;
  late final AnimationController _wind;
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clouds = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 55),
    )..repeat();
    _wind = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat(reverse: true);
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clouds.dispose();
    _wind.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _setRunning(state == AppLifecycleState.resumed && !reduceMotion);
  }

  void _setRunning(bool run) {
    void apply(AnimationController c, {bool reverse = false}) {
      if (run) {
        if (!c.isAnimating) {
          reverse ? c.repeat(reverse: true) : c.repeat();
        }
      } else if (c.isAnimating) {
        c.stop();
      }
    }

    apply(_clouds);
    apply(_wind, reverse: true);
    apply(_drift);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    final run = !reduceMotion && tickersEnabled;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final life = WidgetsBinding.instance.lifecycleState;
      final appActive = life == null || life == AppLifecycleState.resumed;
      _setRunning(run && appActive);
    });

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Painted fallback so missing assets never show red error stripes.
          const ColoredBox(color: Color(0xFF6BAED6)),
          // 1) Photorealistic landscape — fills the screen.
          Positioned.fill(
            child: Image.asset(
              AnimatedSkyBackdrop.skyAsset,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.15),
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) =>
                  const _SkyFallbackPaint(),
            ),
          ),
          // Soft depth wash (keeps glass readable without hiding greenery).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x221E5A8A),
                  Color(0x00FFFFFF),
                  Color(0x281B4D2E),
                ],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
          // 2) Drifting soft cloud layer across the sky.
          AnimatedBuilder(
            animation: _clouds,
            builder: (context, _) {
              return CustomPaint(
                painter: _DriftingCloudPainter(
                  progress: reduceMotion ? 0.12 : _clouds.value,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
          // 3) Sunlight / atmospheric haze (top-right).
          AnimatedBuilder(
            animation: _wind,
            builder: (context, _) {
              final pulse = reduceMotion ? 0.55 : (0.48 + _wind.value * 0.22);
              return CustomPaint(
                painter: _SunHazePainter(intensity: pulse),
                child: const SizedBox.expand(),
              );
            },
          ),
          // 4) Foreground canopy sway — clipped bottom/edge crop of the same photo.
          AnimatedBuilder(
            animation: _wind,
            builder: (context, _) {
              final sway = reduceMotion ? 0.0 : (_wind.value - 0.5) * 2;
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Left canopy tip sway.
                  Align(
                    alignment: Alignment.topLeft,
                    child: Transform.translate(
                      offset: Offset(sway * 5, sway.abs() * 2),
                      child: Transform.rotate(
                        angle: sway * 0.018,
                        alignment: Alignment.topLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.38,
                          heightFactor: 0.34,
                          alignment: Alignment.topLeft,
                          child: Opacity(
                            opacity: 0.92,
                            child: Image.asset(
                              AnimatedSkyBackdrop.skyAsset,
                              fit: BoxFit.cover,
                              alignment: Alignment.topLeft,
                              errorBuilder: (c, e, s) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Right canopy tip sway.
                  Align(
                    alignment: Alignment.topRight,
                    child: Transform.translate(
                      offset: Offset(-sway * 4.5, sway.abs() * 2),
                      child: Transform.rotate(
                        angle: -sway * 0.016,
                        alignment: Alignment.topRight,
                        child: FractionallySizedBox(
                          widthFactor: 0.36,
                          heightFactor: 0.32,
                          alignment: Alignment.topRight,
                          child: Opacity(
                            opacity: 0.9,
                            child: Image.asset(
                              AnimatedSkyBackdrop.skyAsset,
                              fit: BoxFit.cover,
                              alignment: Alignment.topRight,
                              errorBuilder: (c, e, s) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom foliage band sway.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Transform.translate(
                      offset: Offset(sway * 3, 0),
                      child: FractionallySizedBox(
                        widthFactor: 1.08,
                        heightFactor: 0.22,
                        alignment: Alignment.bottomCenter,
                        child: Opacity(
                          opacity: 0.85,
                          child: Image.asset(
                            AnimatedSkyBackdrop.skyAsset,
                            fit: BoxFit.cover,
                            alignment: Alignment.bottomCenter,
                            errorBuilder: (c, e, s) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // 5) Wind-blown floating leaves.
          AnimatedBuilder(
            animation: Listenable.merge([_drift, _wind]),
            builder: (context, _) {
              return CustomPaint(
                painter: _FloatingLeavesPainter(
                  drift: reduceMotion ? 0.18 : _drift.value,
                  sway: reduceMotion ? 0.0 : _wind.value,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SkyFallbackPaint extends StatelessWidget {
  const _SkyFallbackPaint();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _FallbackLandscapePainter(),
      child: SizedBox.expand(),
    );
  }
}

class _FallbackLandscapePainter extends CustomPainter {
  const _FallbackLandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        const [
          Color(0xFF4FA0D8),
          Color(0xFF8EC8F0),
          Color(0xFFC5E4C8),
          Color(0xFF4F8F55),
        ],
        const [0.0, 0.4, 0.7, 1.0],
      );
    canvas.drawRect(Offset.zero & size, sky);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DriftingCloudPainter extends CustomPainter {
  _DriftingCloudPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    void cloud(double yFrac, double scale, double speed, double phase) {
      final travel = ((progress * speed) + phase) % 1.45;
      final x = size.width * (travel - 0.22);
      final y = size.height * yFrac;
      final w = size.width * 0.48 * scale;
      final h = size.height * 0.07 * scale;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18 + 0.12 * scale)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: h),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + w * 0.3, y + h * 0.12),
          width: w * 0.72,
          height: h * 0.88,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x - w * 0.24, y + h * 0.06),
          width: w * 0.58,
          height: h * 0.72,
        ),
        paint,
      );
    }

    cloud(0.09, 1.05, 1.0, 0.0);
    cloud(0.16, 0.78, 0.72, 0.32);
    cloud(0.07, 0.58, 1.2, 0.58);
    cloud(0.2, 0.92, 0.55, 0.18);
  }

  @override
  bool shouldRepaint(covariant _DriftingCloudPainter old) =>
      old.progress != progress;
}

class _SunHazePainter extends CustomPainter {
  _SunHazePainter({required this.intensity});
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.9, size.height * 0.06);
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        origin,
        size.width * 0.62,
        [
          const Color(0xFFFFF6D8).withValues(alpha: 0.5 * intensity),
          const Color(0xFFFFE9A8).withValues(alpha: 0.16 * intensity),
          const Color(0x00FFFFFF),
        ],
        const [0.0, 0.32, 1.0],
      );
    canvas.drawCircle(origin, size.width * 0.62, glow);

    final ray = Paint()
      ..color = const Color(0xFFFFF8E8).withValues(alpha: 0.06 * intensity)
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = -math.pi * 0.12 - i * 0.16;
      final len = size.height * (0.38 + i * 0.035);
      canvas.drawLine(
        origin,
        origin + Offset(math.cos(a) * len, math.sin(a) * len),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SunHazePainter old) =>
      old.intensity != intensity;
}

class _FloatingLeavesPainter extends CustomPainter {
  _FloatingLeavesPainter({required this.drift, required this.sway});
  final double drift;
  final double sway;

  @override
  void paint(Canvas canvas, Size size) {
    final leaves = <(double, double, double, double)>[
      (0.18, 0.36, 1.0, 0.0),
      (0.7, 0.32, 0.75, 0.28),
      (0.42, 0.48, 0.6, 0.5),
      (0.86, 0.44, 0.7, 0.18),
      (0.3, 0.58, 0.55, 0.65),
      (0.58, 0.4, 0.5, 0.8),
    ];
    for (final (xf, yf, sc, phase) in leaves) {
      final t = (drift + phase) % 1.0;
      final x = size.width * (xf + math.sin((t + sway) * math.pi * 2) * 0.035);
      final y = size.height * (yf + t * 0.14);
      _leaf(canvas, Offset(x, y), 6.5 * sc, (t + sway) * math.pi * 0.9);
    }
  }

  void _leaf(Canvas canvas, Offset c, double r, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(r * 0.95, -r * 0.15, 0, r)
      ..quadraticBezierTo(-r * 0.95, -r * 0.15, 0, -r)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF3A8F4E).withValues(alpha: 0.62),
    );
    canvas.drawLine(
      Offset(0, -r * 0.65),
      Offset(0, r * 0.65),
      Paint()
        ..color = const Color(0xFF1E5A30).withValues(alpha: 0.4)
        ..strokeWidth = 0.9,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FloatingLeavesPainter old) =>
      old.drift != drift || old.sway != sway;
}
