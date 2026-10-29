import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/aqi.dart';
import '../models/period_logic.dart';
import '../theme.dart';
import 'common.dart';

/// Historical AQI palette (AQISection.jsx); differs from the Live gauge.
AqiCategory historicalAqiCategory(num aqi) {
  if (aqi <= 50) return const AqiCategory('Good', Color(0xFF10B981));
  if (aqi <= 100) return const AqiCategory('Moderate', Color(0xFFF59E0B));
  if (aqi <= 150) return const AqiCategory('Poor', Color(0xFFF97316));
  if (aqi <= 200) return const AqiCategory('Unhealthy', Color(0xFFEF4444));
  if (aqi <= 300) return const AqiCategory('Severe', Color(0xFF8B5CF6));
  return const AqiCategory('Hazardous', Color(0xFF7F1D1D));
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.title,
    required this.child,
    required this.footer,
    this.onTap,
  });

  final String title;
  final Widget child;
  final String footer;
  final VoidCallback? onTap;

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
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                  ),
                  child: const Text('DAILY AVERAGE',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ]),
              const SizedBox(height: 18),
              child,
              const SizedBox(height: 16),
              Text(footer, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _stateBox({
  required bool loading,
  required String? error,
  required String loadingLabel,
  required String emptyLabel,
  VoidCallback? onRetry,
}) {
  if (loading) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(loadingLabel, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          const Text('Calculating daily averages...',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      ),
    );
  }
  if (error != null) return ErrorBox(message: error, onRetry: onRetry);
  return EmptyBox(message: emptyLabel);
}

class AqiSummaryCard extends StatelessWidget {
  const AqiSummaryCard({
    super.key,
    required this.data,
    required this.loading,
    required this.date,
    this.error,
    this.onTap,
    this.onRetry,
  });

  final AqiAggregate? data;
  final bool loading;
  final String? error;
  final DateTime date;
  final VoidCallback? onTap, onRetry;

  static const _scale = <(String, String, Color)>[
    ('Good', '0-50', Color(0xFF10B981)),
    ('Moderate', '51-100', Color(0xFFF59E0B)),
    ('Poor', '101-150', Color(0xFFF97316)),
    ('Unhealthy', '151-200', Color(0xFFEF4444)),
    ('Severe', '201-300', Color(0xFF8B5CF6)),
    ('Hazardous', '301+', Color(0xFF7F1D1D)),
  ];

  /// `value || null` then `toFixed(2)` or "N/A" (AQISection.jsx).
  static String _p(double v) => v == 0 || v.isNaN ? 'N/A' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final d = data;
    final footer = 'Date: ${DateFormat.yMd().format(date)}';
    if (loading || d == null || d.aqi == 0) {
      return _PeriodCard(
        title: 'Air Quality Index',
        footer: footer,
        child: _stateBox(
          loading: loading,
          error: error,
          loadingLabel: 'Loading AQI data...',
          emptyLabel: 'No AQI records returned for this period',
          onRetry: onRetry,
        ),
      );
    }
    final cat = historicalAqiCategory(d.aqi);
    final pollutants = <(String, String, String)>[
      ('PM2.5', _p(d.pm25), 'µg/m³'),
      ('PM10', _p(d.pm10), 'µg/m³'),
      ('CO', _p(d.co), 'ppm'),
      ('SO₂', _p(d.so2), 'µg/m³'),
      ('NO₂', _p(d.no2), 'µg/m³'),
      ('O₃', _p(d.o3), 'µg/m³'),
    ];
    return _PeriodCard(
      title: 'Air Quality Index',
      footer: footer,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('${d.aqi}',
                style: TextStyle(
                    fontSize: 56, fontWeight: FontWeight.w800, color: cat.color, height: 1)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cat.color),
              ),
              child: Text('Air Quality is ${cat.label}',
                  style: TextStyle(color: cat.color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 3 : 2;
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (label, value, unit) in pollutants)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Text('$value $unit',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]);
        }),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, c) {
          final pos = (d.aqi / 300).clamp(0.0, 1.0) * c.maxWidth;
          return SizedBox(
            height: 48,
            child: Stack(clipBehavior: Clip.none, children: [
              Row(children: [
                for (final (label, range, color) in _scale)
                  Expanded(
                    child: Container(
                      height: 40,
                      color: color,
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(label,
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w700)),
                            Text(range, style: const TextStyle(fontSize: 9)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
              Positioned(
                left: pos - 7,
                top: 33,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cat.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class WeatherSummaryCard extends StatelessWidget {
  const WeatherSummaryCard({
    super.key,
    required this.data,
    required this.loading,
    required this.date,
    this.error,
    this.warning,
    this.onTap,
    this.onRetry,
  });

  final WeatherAggregate? data;
  final bool loading;
  final String? error;

  /// Shown above the values when some day requests failed.
  final String? warning;
  final DateTime date;
  final VoidCallback? onTap, onRetry;

  static Color _tempColor(num t) {
    if (t >= 35) return const Color(0xFFEF4444);
    if (t >= 25) return const Color(0xFFF59E0B);
    if (t >= 15) return const Color(0xFF14B8A6);
    return const Color(0xFF60A5FA);
  }

  static String _tempLabel(num t) {
    if (t >= 35) return 'Hot';
    if (t >= 25) return 'Warm';
    if (t >= 15) return 'Moderate';
    return 'Cool';
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final footer = 'Date: ${DateFormat.yMd().format(date)}';
    if (loading || d == null) {
      return _PeriodCard(
        title: 'Weather Conditions',
        footer: footer,
        child: _stateBox(
          loading: loading,
          error: error,
          loadingLabel: 'Loading weather data...',
          emptyLabel: 'No weather records returned for this period',
          onRetry: onRetry,
        ),
      );
    }
    final color = _tempColor(d.temperature);
    final metrics = <(String, String)>[
      ('Feels Like', '${d.feelsLike.toStringAsFixed(2)}°C'),
      ('Humidity', '${d.humidity.toStringAsFixed(2)}%'),
      ('Wind Speed', '${d.windSpeed.toStringAsFixed(2)} km/h'),
      ('UV Index', d.uvIndex.toStringAsFixed(2)),
    ];
    return _PeriodCard(
      title: 'Weather Conditions',
      footer: footer,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (warning != null) ...[
          ErrorBox(message: warning!, onRetry: onRetry),
          const SizedBox(height: 14),
        ],
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 10,
          children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d.temperature}',
                  style: TextStyle(
                      fontSize: 56, fontWeight: FontWeight.w800, color: color, height: 1)),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('°C', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(_tempLabel(d.temperature),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(d.icon == 'cloud' ? Icons.cloud_outlined : Icons.wb_sunny_outlined,
                  size: 28, color: AppColors.softMint),
              const SizedBox(width: 8),
              Text(d.condition, style: const TextStyle(fontSize: 15)),
            ]),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 4 : 2;
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (label, value) in metrics)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]);
        }),
      ]),
    );
  }
}
