import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/aqi.dart';
import 'dark_osm_tiles.dart';

/// Shared light glass surface for the Design 1 / Design 5 home chrome.
class LightGlassSurface {
  /// 0% opacity background so the map stays completely visible underneath.
  static BoxDecoration card({double radius = 18, Color? border}) => BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: border ?? Colors.white.withValues(alpha: 0.55),
          width: 1.1,
        ),
      );
}

/// Pollutant fields shown on the home details page (key, label, unit).
const kHomePollutantFields = <(String, String, String)>[
  ('pm2_5', 'PM2.5', 'µg/m³'),
  ('pm10', 'PM10', 'µg/m³'),
  ('no2', 'NO₂', 'µg/m³'),
  ('so2', 'SO₂', 'µg/m³'),
  ('o3', 'O₃', 'µg/m³'),
  ('co', 'CO', 'ppm'),
];

/// Subtle cyan location pulse at map centre while GPS / place resolve.
/// No loading text — map stays visible and interactive underneath.
class HomeGpsLocatingIndicator extends StatefulWidget {
  const HomeGpsLocatingIndicator({super.key, this.size = 120});

  final double size;

  @override
  State<HomeGpsLocatingIndicator> createState() =>
      _HomeGpsLocatingIndicatorState();
}

class _HomeGpsLocatingIndicatorState extends State<HomeGpsLocatingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cyan = LightOsmTileLayer.accent;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final s = widget.size;
        return SizedBox(
          width: s,
          height: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft core glow.
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cyan.withValues(alpha: 0.22),
                  boxShadow: [
                    BoxShadow(
                      color: cyan.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              // Compact pin — clean location marker without decorative outer rings.
              Icon(
                Icons.location_on_rounded,
                size: 28,
                color: cyan,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.9),
                    blurRadius: 8,
                  ),
                  Shadow(
                    color: cyan.withValues(alpha: 0.45),
                    blurRadius: 10,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact retry chip when GPS permission / fix fails (not a wide banner).
class HomeGpsRetryChip extends StatelessWidget {
  const HomeGpsRetryChip({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(22),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined,
                  size: 18, color: LightOsmTileLayer.accent),
              const SizedBox(width: 8),
              const Text(
                'Retry location',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Central glass AQI circle with a soft pulse; category sits beneath the ring.
class HomeAqiGauge extends StatefulWidget {
  const HomeAqiGauge({
    super.key,
    required this.aqi,
    this.category,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onTap,
    this.size = 150,
    this.cardStyle = false,
  });

  final double? aqi;
  final AqiCategory? category;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onTap;
  final double size;
  final bool cardStyle;

  @override
  State<HomeAqiGauge> createState() => _HomeAqiGaugeState();
}

class _HomeAqiGaugeState extends State<HomeAqiGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseCurve;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!widget.cardStyle) {
      _pulse.repeat(reverse: true);
    }
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _pulseActive =>
      !widget.cardStyle && !widget.loading && widget.error == null && widget.aqi != null;

  @override
  Widget build(BuildContext context) {
    if (widget.cardStyle) {
      final aqiVal = widget.aqi;
      final fraction = aqiVal == null
          ? 0.35
          : (aqiVal / 250.0).clamp(0.04, 1.0);
      final size = widget.size;

      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _AqiCardArcPainter(fraction: fraction),
            ),
            Container(
              width: size * 0.76,
              height: size * 0.76,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'AQI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.aqi == null ? '—' : '${widget.aqi!.round()}',
                        style: TextStyle(
                          fontSize: size * 0.24,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                          height: 1.0,
                        ),
                      ),
                      if (widget.category != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.category!.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: widget.category!.color,
                            height: 1.0,
                          ),
                        ),
                        Container(
                          width: 34,
                          height: 1.5,
                          margin: const EdgeInsets.only(top: 3),
                          color: const Color(0xFFE2E8F0),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final color = widget.category?.color ?? LightOsmTileLayer.accent;
    final fraction = widget.aqi == null
        ? 0.0
        : (aqiGaugeAngle(widget.aqi!) / 180).clamp(0.0, 1.0);
    final size = widget.size;
    // Fixed square: geometric centre of rings/gauge == widget centre
    final frame = size * 1.55;

    return SizedBox(
      width: frame,
      height: frame,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: widget.loading
                ? null
                : (widget.error != null ? widget.onRetry : widget.onTap),
            child: AnimatedBuilder(
              animation: _pulseCurve,
              builder: (context, child) {
                final t = _pulseActive ? _pulseCurve.value : 0.0;
                final scale = 1.0 + (t * 0.04);
                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: child,
                  ),
                );
              },
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 0% background fill opacity so map shows through.
                  color: Colors.transparent,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 1.5,
                  ),
                ),
                child: CustomPaint(
                  painter:
                      _HomeRingPainter(fraction: fraction, color: color),
                  child: Center(child: _gaugeBody(size)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gaugeBody(double size) {
    if (widget.loading) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: LightOsmTileLayer.accent),
      );
    }
    if (widget.error != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined,
            color: Color(0xFF64748B), size: 28),
        const SizedBox(height: 6),
        Text('AQI unavailable',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0F172A),
                shadows: [
                  Shadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      blurRadius: 6),
                ])),
        if (widget.onRetry != null)
          const Text('Tap to retry',
              style: TextStyle(
                  fontSize: 11, color: LightOsmTileLayer.accent)),
      ]);
    }
    // Design 3: Exact hierarchy inside gauge disc:
    // 144
    // AQI
    // Poor
    // Tap for details
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        widget.aqi == null ? '—' : '${widget.aqi!.round()}',
        style: TextStyle(
          fontSize: size * 0.28,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0F172A),
          height: 1.0,
        ),
      ),
      const SizedBox(height: 3),
      const Text(
        'AQI',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
          letterSpacing: 0.2,
          height: 1.0,
        ),
      ),
      if (widget.category != null) ...[
        const SizedBox(height: 2),
        Text(
          widget.category!.label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
      ],
      if (widget.onTap != null) ...[
        const SizedBox(height: 3),
        const Text(
          'Tap for details',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0D9488),
            letterSpacing: 0.1,
          ),
        ),
      ],
    ]);
  }
}

/// Floating location label — pin + city/state text (Design 3 style).
class HomeLocationNameChip extends StatelessWidget {
  const HomeLocationNameChip({
    super.key,
    required this.name,
  });

  final String name;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 20,
            color: const Color(0xFF0D9488),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 8,
              ),
            ],
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
                color: Colors.white,
                height: 1.15,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 10,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact History | Prediction control for the map bottom overlay.
/// In Design 3 (Satellite - Green), History is selected with a lush green accent.
class HomeHistoryPredictionBar extends StatelessWidget {
  const HomeHistoryPredictionBar({
    super.key,
    required this.onHistory,
    required this.onPrediction,
    this.selectedMode = 'history',
    this.accentColor = const Color(0xFF0D5E34),
  });

  final VoidCallback onHistory;
  final VoidCallback onPrediction;
  final String selectedMode;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegButton(
              label: 'History',
              icon: Icons.history_rounded,
              onTap: onHistory,
              filled: selectedMode == 'history',
              accentColor: accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SegButton(
              label: 'Prediction',
              icon: Icons.timeline_rounded,
              onTap: onPrediction,
              filled: selectedMode == 'prediction',
              accentColor: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.accentColor = const Color(0xFF02A78D),
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    // Solid accent for selected state; 0% opacity for unselected.
    final bg = filled ? accentColor : Colors.transparent;
    final fg = Colors.white;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom pollutant strip (6 cards in one row) — screen overlay, not map-anchored.
class HomePollutantBar extends StatelessWidget {
  const HomePollutantBar({
    super.key,
    required this.record,
    this.placeName,
    this.onRetryAqi,
    this.aqiError,
  });

  final AqiRecord? record;
  final String? placeName;
  final VoidCallback? onRetryAqi;
  final String? aqiError;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (placeName != null && placeName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              placeName!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: wide ? 18 : 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.85),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        if (record != null)
          SizedBox(
            width: math.min(MediaQuery.sizeOf(context).width - 24, 680.0),
            child: _PollutantStrip(record: record!, compact: !wide),
          )
        else if (aqiError != null && onRetryAqi != null)
          TextButton.icon(
            onPressed: onRetryAqi,
            icon: const Icon(Icons.refresh, size: 18, color: LightOsmTileLayer.accent),
            label: const Text('Retry AQI',
                style: TextStyle(color: LightOsmTileLayer.accent)),
          ),
      ],
    );
  }
}

/// Combined gauge + pollutants (tests / non-map previews).
class HomeAqiDashboard extends StatelessWidget {
  const HomeAqiDashboard({
    super.key,
    required this.record,
    this.placeName,
    this.onRetryAqi,
    this.aqiError,
    this.loadingAqi = false,
  });

  final AqiRecord? record;
  final String? placeName;
  final VoidCallback? onRetryAqi;
  final String? aqiError;
  final bool loadingAqi;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final aqi = record?.aqi;
    final cat = aqi != null ? aqiCategory(aqi) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeAqiGauge(
          aqi: aqi,
          category: cat,
          loading: loadingAqi,
          error: aqiError,
          onRetry: onRetryAqi,
          size: wide ? 168.0 : 150.0,
        ),
        SizedBox(height: wide ? 18 : 14),
        HomePollutantBar(
          record: record,
          placeName: placeName,
          onRetryAqi: onRetryAqi,
          aqiError: aqiError,
        ),
      ],
    );
  }
}

class _AqiCardArcPainter extends CustomPainter {
  _AqiCardArcPainter({required this.fraction});
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final radius = (size.width - stroke) / 2;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Sweep from 135 deg (bottom-left) around top to 45 deg (bottom-right) => 270 deg
    const startAngle = 135 * (math.pi / 180);
    const totalSweep = 270 * (math.pi / 180);

    // 1. Background track: subtle grey arc
    final trackPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, totalSweep, false, trackPaint);

    if (fraction <= 0) return;

    // 2. Active progress arc: multi-color gradient
    // Green (Good) -> Yellow (Moderate) -> Orange (Poor) -> Red (Unhealthy)
    final activeSweep = totalSweep * fraction.clamp(0.02, 1.0);
    final gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + totalSweep,
      colors: const [
        Color(0xFF22C55E), // Green
        Color(0xFFEAB308), // Yellow
        Color(0xFFF97316), // Orange
        Color(0xFFEF4444), // Red
      ],
      stops: const [0.0, 0.33, 0.66, 1.0],
    );

    final activePaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _AqiCardArcPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _HomeRingPainter extends CustomPainter {
  _HomeRingPainter({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - stroke - 4,
    );
    const start = -math.pi / 2;
    canvas.drawArc(
      rect,
      start,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0xFF94A3B8).withValues(alpha: 0.35),
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      start,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeRingPainter old) =>
      old.fraction != fraction || old.color != color;
}

class _PollutantStrip extends StatelessWidget {
  const _PollutantStrip({required this.record, required this.compact});
  final AqiRecord record;
  final bool compact;

  static const _spacing = 6.0;
  /// Smallest readable card width; below this we scroll instead of wrapping.
  static const _minCardW = 52.0;
  static const _scrollCardW = 64.0;
  static const _items = kHomePollutantFields;

  double? _value(String key) {
    final v = record.value(key);
    if (key == 'pm2_5' && (v == null || v == 0)) {
      return record.pm25 ?? record.value('pm25') ?? v;
    }
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

  @override
  Widget build(BuildContext context) {
    // Single horizontal row of exactly 6 columns — never wrap.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final fitMin =
            _minCardW * _items.length + _spacing * (_items.length - 1);
        final canFit = maxW.isFinite && maxW >= fitMin;

        _PollutantChip chip((String, String, String) item) => _PollutantChip(
              label: item.$2,
              unit: item.$3,
              value: _value(item.$1),
              compact: compact,
            );

        if (canFit) {
          return Row(
            children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0) const SizedBox(width: _spacing),
                Expanded(child: chip(_items[i])),
              ],
            ],
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0) const SizedBox(width: _spacing),
                SizedBox(width: _scrollCardW, child: chip(_items[i])),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PollutantChip extends StatelessWidget {
  const _PollutantChip({
    required this.label,
    required this.unit,
    required this.value,
    required this.compact,
  });

  final String label, unit;
  final double? value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = value == null || value!.isNaN
        ? '—'
        : value!.toStringAsFixed(value!.abs() >= 100 ? 0 : 1);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 8 : 10,
        compact ? 8 : 10,
        compact ? 7 : 9,
      ),
      decoration: LightGlassSurface.card(radius: 14),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: compact ? 2 : 3),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                unit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w600,
                  color: LightOsmTileLayer.accent,
                ),
              ),
            ],
          ),
        );
  }
}
