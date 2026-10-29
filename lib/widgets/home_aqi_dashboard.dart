import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/aqi.dart';
import 'dark_osm_tiles.dart';

/// Shared light glass surface for the Design 1 / Design 5 home chrome.
class LightGlassSurface {
  static BoxDecoration card({double radius = 18, Color? border}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? LightOsmTileLayer.accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
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

/// Compact themed GPS locating indicator (replaces the old wide fetch banner).
class HomeGpsLocatingIndicator extends StatefulWidget {
  const HomeGpsLocatingIndicator({super.key});

  @override
  State<HomeGpsLocatingIndicator> createState() =>
      _HomeGpsLocatingIndicatorState();
}

class _HomeGpsLocatingIndicatorState extends State<HomeGpsLocatingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _curve = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        final ring = 42.0 + (t * 14);
        return SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft pulse rings
              Container(
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LightOsmTileLayer.accent
                      .withValues(alpha: 0.14 * (1 - t * 0.35)),
                  border: Border.all(
                    color: LightOsmTileLayer.accent
                        .withValues(alpha: 0.35 * (1 - t * 0.4)),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.92),
                  border: Border.all(
                    color: LightOsmTileLayer.accent.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: LightOsmTileLayer.accent
                          .withValues(alpha: 0.22 + t * 0.18),
                      blurRadius: 12 + t * 8,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 26 + t * 2,
                  color: LightOsmTileLayer.accent,
                ),
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
  });

  final double? aqi;
  final AqiCategory? category;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onTap;
  final double size;

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
    )..repeat(reverse: true);
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _pulseActive =>
      !widget.loading && widget.error == null && widget.aqi != null;

  @override
  Widget build(BuildContext context) {
    final color = widget.category?.color ?? LightOsmTileLayer.accent;
    final fraction = widget.aqi == null
        ? 0.0
        : (aqiGaugeAngle(widget.aqi!) / 180).clamp(0.0, 1.0);
    final size = widget.size;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.loading
              ? null
              : (widget.error != null ? widget.onRetry : widget.onTap),
          child: AnimatedBuilder(
            animation: _pulseCurve,
            builder: (context, child) {
              final t = _pulseActive ? _pulseCurve.value : 0.0;
              final scale = 1.0 + (t * 0.06);
              final glow = 0.32 + (t * 0.38);
              final beam = size * (1.08 + t * 0.42);
              return SizedBox(
                width: size * 1.55,
                height: size * 1.55,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Expanding beam ring
                    Opacity(
                      opacity: _pulseActive ? (1.0 - t) * 0.55 : 0,
                      child: Container(
                        width: beam,
                        height: beam,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(alpha: 0.65),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35 * (1 - t)),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Soft halo
                    Container(
                      width: size * (1.12 + t * 0.1),
                      height: size * (1.12 + t * 0.1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.12 + t * 0.14),
                      ),
                    ),
                    Transform.scale(
                      scale: scale,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: glow),
                              blurRadius: 28 + (t * 26),
                              spreadRadius: 2 + (t * 8),
                            ),
                            BoxShadow(
                              color: color.withValues(alpha: 0.25 + t * 0.2),
                              blurRadius: 48 + (t * 20),
                              spreadRadius: 0,
                            ),
                            BoxShadow(
                              color:
                                  const Color(0xFF0F172A).withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              );
            },
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.88),
                        const Color(0xFFE0F7F4).withValues(alpha: 0.72),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.5,
                    ),
                  ),
                  child: CustomPaint(
                    painter: _HomeRingPainter(fraction: fraction, color: color),
                    child: Center(child: _gaugeBody(size)),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.category != null &&
            !widget.loading &&
            widget.error == null) ...[
          const SizedBox(height: 8),
          Text(
            widget.category!.label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              shadows: [
                Shadow(
                  color: Color(0xE6FFFFFF),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ],
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
        const Text('AQI unavailable',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A))),
        if (widget.onRetry != null)
          const Text('Tap to retry',
              style: TextStyle(
                  fontSize: 11, color: LightOsmTileLayer.accent)),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        widget.aqi == null ? '—' : '${widget.aqi!.round()}',
        style: TextStyle(
          fontSize: size * 0.28,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0F172A),
          height: 1,
        ),
      ),
      const Text('AQI',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B))),
      if (widget.onTap != null) ...[
        const SizedBox(height: 2),
        Text('Tap for details',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: LightOsmTileLayer.accent.withValues(alpha: 0.85))),
      ],
    ]);
  }
}

/// Floating place-name chip shown outside the GPS / AQI circle.
class HomeLocationNameChip extends StatelessWidget {
  const HomeLocationNameChip({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: LightGlassSurface.card(radius: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place_outlined,
                  size: 16, color: LightOsmTileLayer.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact History | Prediction control for the map bottom overlay.
class HomeHistoryPredictionBar extends StatelessWidget {
  const HomeHistoryPredictionBar({
    super.key,
    required this.onHistory,
    required this.onPrediction,
  });

  final VoidCallback onHistory;
  final VoidCallback onPrediction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: LightGlassSurface.card(radius: 22),
          child: Row(
            children: [
              Expanded(
                child: _SegButton(
                  label: 'History',
                  icon: Icons.history_rounded,
                  onTap: onHistory,
                  filled: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegButton(
                  label: 'Prediction',
                  icon: Icons.timeline_rounded,
                  onTap: onPrediction,
                ),
              ),
            ],
          ),
        ),
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
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? LightOsmTileLayer.accent
        : const Color(0xFF0F172A).withValues(alpha: 0.06);
    final fg = filled ? Colors.white : const Color(0xFF0F172A);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
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
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + math.pi * 2,
          colors: [color.withValues(alpha: 0.55), color],
        ).createShader(rect),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
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
        ),
      ),
    );
  }
}
