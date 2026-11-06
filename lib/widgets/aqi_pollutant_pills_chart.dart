import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/aqi.dart';
import 'home_aqi_dashboard.dart';

/// Mandatory color references from Showcase Designs 11-14, 17, 18.
class AqiChartTheme {
  const AqiChartTheme({
    required this.id,
    required this.name,
    required this.barColor,
    required this.lineColor,
    required this.dotStrokeColor,
    required this.selectedButtonAccent,
    required this.pillActiveColor,
  });

  final String id;
  final String name;
  final Color barColor;
  final Color lineColor;
  final Color dotStrokeColor;
  final Color selectedButtonAccent;
  final Color pillActiveColor;

  /// Design 11 — Prediction (Satellite - Blue)
  static const satelliteBlue = AqiChartTheme(
    id: 'satellite_blue',
    name: 'Design 11 — Satellite Blue',
    barColor: Color(0xFF388CFC),
    lineColor: Color(0xFF2377B5),
    dotStrokeColor: Color(0xFF2377B5),
    selectedButtonAccent: Color(0xFF1F85FB),
    pillActiveColor: Color(0xFF0A66FD),
  );

  /// Design 12 — Prediction (Satellite - Green)
  static const satelliteGreen = AqiChartTheme(
    id: 'satellite_green',
    name: 'Design 12 — Satellite Green',
    barColor: Color(0xFF01C7AD),
    lineColor: Color(0xFF00AAA8),
    dotStrokeColor: Color(0xFF00AAA8),
    selectedButtonAccent: Color(0xFF56CE82),
    pillActiveColor: Color(0xFF16F0A1),
  );

  /// Design 13 — Prediction (Satellite - Orange)
  static const satelliteOrange = AqiChartTheme(
    id: 'satellite_orange',
    name: 'Design 13 — Satellite Orange',
    barColor: Color(0xFFFAAC46),
    lineColor: Color(0xFFD4A233),
    dotStrokeColor: Color(0xFFE47A2B),
    selectedButtonAccent: Color(0xFFEAAD49),
    pillActiveColor: Color(0xFFFD8903),
  );

  /// Design 14 — Prediction (Satellite - Purple)
  static const satellitePurple = AqiChartTheme(
    id: 'satellite_purple',
    name: 'Design 14 — Satellite Purple',
    barColor: Color(0xFF785FF9),
    lineColor: Color(0xFF6F55AE),
    dotStrokeColor: Color(0xFF6F55AE),
    selectedButtonAccent: Color(0xFF6667F9),
    pillActiveColor: Color(0xFFA263FD),
  );

  /// Design 9 — History (Showcase panel 09)
  static const design9History = AqiChartTheme(
    id: 'design_9_history',
    name: 'Design 9 — History',
    barColor: Color(0xFF388CFC),
    lineColor: Color(0xFF2563EB),
    dotStrokeColor: Color(0xFF2563EB),
    selectedButtonAccent: Color(0xFF0284C7),
    pillActiveColor: Color(0xFF2563EB),
  );

  /// Design 15 — Prediction (Showcase panel 15)
  static const design15Prediction = AqiChartTheme(
    id: 'design_15_prediction',
    name: 'Design 15 — Prediction',
    barColor: Color(0xFF388CFC),
    lineColor: Color(0xFF2563EB),
    dotStrokeColor: Color(0xFF2563EB),
    selectedButtonAccent: Color(0xFF0284C7),
    pillActiveColor: Color(0xFF2563EB),
  );

  static AqiChartTheme resolve({
    required bool isSatellite,
    required bool isHistory,
    required String selectedKey,
  }) {
    // Exact mapping: Design 9 -> History Screen; Design 15 -> Prediction Screen
    return isHistory ? design9History : design15Prediction;
  }

  static Color pillColorFor(
    String key, {
    required bool isSatellite,
    required bool isHistory,
  }) {
    final theme = resolve(
      isSatellite: isSatellite,
      isHistory: isHistory,
      selectedKey: key,
    );
    return theme.pillActiveColor;
  }
}

/// Glassmorphism Pro — History / Prediction pollutant trend.
class AqiPollutantPillsChart extends StatelessWidget {
  const AqiPollutantPillsChart({
    super.key,
    required this.isHistory,
    required this.selectedKey,
    required this.onSelect,
    required this.samples,
    required this.loading,
    this.record,
    this.placeName,
    this.isSatellite = true,
    this.error,
    this.onRetry,
    this.onHistoryChanged,
  });

  final bool isHistory;
  final String selectedKey;
  final ValueChanged<String> onSelect;
  final List<AqiHourSample> samples;
  final bool loading;
  final AqiRecord? record;
  final String? placeName;
  final bool isSatellite;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<bool>? onHistoryChanged;

  @override
  Widget build(BuildContext context) {
    final selected = kHomePollutantFields.firstWhere(
      (f) => f.$1 == selectedKey,
      orElse: () => kHomePollutantFields[0],
    );
    final theme = AqiChartTheme.resolve(
      isSatellite: isSatellite,
      isHistory: isHistory,
      selectedKey: selectedKey,
    );

    final aqiVal = record?.aqi;
    final cat = aqiVal != null ? aqiCategory(aqiVal) : null;
    final textColor = isSatellite ? Colors.white : const Color(0xFF0F172A);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header and pollutant buttons: Position pollutant selection buttons directly below header
          _PillGrid(
            selectedKey: selectedKey,
            onSelect: onSelect,
            isSatellite: isSatellite,
            isHistory: isHistory,
          ),
          const SizedBox(height: 10),

          // 2. Location: Display current fetched location name below pollutant buttons with location marker
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 16,
                color: isSatellite ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  (placeName != null && placeName!.trim().isNotEmpty)
                      ? placeName!
                      : 'Nashik, Maharashtra',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. AQI CIRCLE — MOST IMPORTANT: Large, clearly visible circular element centered between location and graph
          Center(
            child: HomeAqiGauge(
              aqi: aqiVal ?? 104,
              category: cat ?? aqiCategory(104),
              size: 140,
              cardStyle: true,
            ),
          ),
          const SizedBox(height: 14),

          // 4. GRAPH POSITION: Graph container moved substantially downward, begins only after AQI circle ends
          SizedBox(
            height: 256,
            width: double.infinity,
            child: _GlassPanel(
              isSatellite: isSatellite,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.$2,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: isSatellite
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            isHistory ? 'Last 6 Hours' : 'Next 6 Hours',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isSatellite
                                  ? Colors.white70
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        selected.$3,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSatellite
                              ? Colors.white.withValues(alpha: 0.8)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: loading
                        ? Center(
                            child: CircularProgressIndicator(
                                color: theme.selectedButtonAccent),
                          )
                        : error != null
                            ? _MessagePane(
                                message: error!,
                                actionLabel: 'Retry',
                                onAction: onRetry,
                              )
                            : samples.isEmpty
                                ? _MessagePane(
                                    message: isHistory
                                        ? 'No hourly pollutant data for this window.'
                                        : 'No upcoming hourly pollutant data available from the API.',
                                  )
                                : _PollutantComboChart(
                                    samples: samples,
                                    pollutantKey: selected.$1,
                                    pollutantLabel: selected.$2,
                                    unit: selected.$3,
                                    theme: theme,
                                    isSatellite: isSatellite,
                                  ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 6. BEST-TIME BANNER: Separate rounded translucent white banner immediately below graph
          _BestTimeBanner(
            samples: samples,
            selectedKey: selectedKey,
            isHistory: isHistory,
            isSatellite: isSatellite,
            accentColor: theme.selectedButtonAccent,
          ),
          const SizedBox(height: 10),

          // 7. BOTTOM NAVIGATION: History and Prediction selector below recommendation banner
          if (onHistoryChanged != null) ...[
            _ModeToggle(
              isHistory: isHistory,
              onChanged: onHistoryChanged!,
              accentColor: theme.selectedButtonAccent,
              isSatellite: isSatellite,
            ),
            const SizedBox(height: 8),
          ],

          // Followed by Last 6 Hours label
          _WindowFooter(isHistory: isHistory, isSatellite: isSatellite),
        ],
      ),
    );
  }
}

/// One hourly sample from `/aqi/hourly` (genuine API fields only).
class AqiHourSample {
  AqiHourSample({required this.time, required this.values});
  final DateTime time;
  final Map<String, double> values;

  double? valueOf(String key) => values[key];
}

/// Evaluates lowest overall pollution level across a 6-hour period
/// and recommends the best time to visit based on all available pollutants
/// and applicable health guidelines.
class BestTimeRecommendation {
  const BestTimeRecommendation({
    required this.time,
    required this.message,
    required this.isReliable,
  });

  final DateTime? time;
  final String message;
  final bool isReliable;

  static BestTimeRecommendation evaluate({
    required List<AqiHourSample> samples,
    required String selectedKey,
    required bool isHistory,
  }) {
    if (samples.isEmpty) {
      return BestTimeRecommendation(
        time: null,
        message: isHistory
            ? 'No historical data available to determine best time.'
            : 'No prediction data available to determine best time.',
        isReliable: false,
      );
    }

    AqiHourSample? bestSample;
    double lowestHarmScore = double.infinity;

    for (final s in samples) {
      final selectedVal = s.valueOf(selectedKey);

      final pm25 = s.valueOf('pm2_5');
      final pm10 = s.valueOf('pm10');
      final no2 = s.valueOf('no2');
      final o3 = s.valueOf('o3');
      final so2 = s.valueOf('so2');
      final co = s.valueOf('co');

      double compositeScore = 0;
      double totalWeight = 0;

      // Safe limits and weights based on standard health guidelines:
      if (pm25 != null && pm25 >= 0) {
        compositeScore += (pm25 / 15.0) * 0.35; // WHO annual/daily target
        totalWeight += 0.35;
      }
      if (pm10 != null && pm10 >= 0) {
        compositeScore += (pm10 / 45.0) * 0.20;
        totalWeight += 0.20;
      }
      if (no2 != null && no2 >= 0) {
        compositeScore += (no2 / 25.0) * 0.15;
        totalWeight += 0.15;
      }
      if (o3 != null && o3 >= 0) {
        compositeScore += (o3 / 60.0) * 0.15;
        totalWeight += 0.15;
      }
      if (so2 != null && so2 >= 0) {
        compositeScore += (so2 / 40.0) * 0.10;
        totalWeight += 0.10;
      }
      if (co != null && co >= 0) {
        compositeScore += (co / 4.0) * 0.05;
        totalWeight += 0.05;
      }

      double finalScore;
      if (totalWeight > 0) {
        final normalizedComposite = compositeScore / totalWeight;
        if (selectedVal != null && selectedVal >= 0) {
          final selDivisor = switch (selectedKey) {
            'pm2_5' => 15.0,
            'pm10' => 45.0,
            'no2' => 25.0,
            'o3' => 60.0,
            'so2' => 40.0,
            'co' => 4.0,
            _ => 25.0,
          };
          final selRatio = selectedVal / selDivisor;
          // Priority to active selected pollutant while incorporating overall health index
          finalScore = (selRatio * 0.75) + (normalizedComposite * 0.25);
        } else {
          finalScore = normalizedComposite;
        }
      } else if (selectedVal != null && selectedVal >= 0) {
        finalScore = selectedVal;
      } else {
        continue;
      }

      if (finalScore < lowestHarmScore) {
        lowestHarmScore = finalScore;
        bestSample = s;
      }
    }

    if (bestSample == null) {
      return const BestTimeRecommendation(
        time: null,
        message: 'Incomplete pollutant data to identify best visit time.',
        isReliable: false,
      );
    }

    final timeStr = DateFormat('h:mm a').format(bestSample.time);
    final msg = isHistory
        ? 'Best time to visit: $timeStr — Air quality was better.'
        : 'Best time to visit: $timeStr — Air quality is expected to be better.';

    return BestTimeRecommendation(
      time: bestSample.time,
      message: msg,
      isReliable: true,
    );
  }
}

/// Professional transparent banner displaying the dynamic best time recommendation.
class _BestTimeBanner extends StatelessWidget {
  const _BestTimeBanner({
    required this.samples,
    required this.selectedKey,
    required this.isHistory,
    required this.isSatellite,
    required this.accentColor,
  });

  final List<AqiHourSample> samples;
  final String selectedKey;
  final bool isHistory;
  final bool isSatellite;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final rec = BestTimeRecommendation.evaluate(
      samples: samples,
      selectedKey: selectedKey,
      isHistory: isHistory,
    );

    final textColor = isSatellite ? Colors.white : const Color(0xFF0F172A);
    final borderColor = isSatellite
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFFCBD5E1);
    final bannerBg = isSatellite
        ? const Color(0xFF0F172A).withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.88);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
        boxShadow: isSatellite
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
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
              Icons.access_time_filled_rounded,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: rec.time != null
                ? Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      children: [
                        const TextSpan(text: 'Best time to visit: '),
                        TextSpan(
                          text: DateFormat('h:mm a').format(rec.time!),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isSatellite
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                        TextSpan(
                          text: isHistory
                              ? ' — Air quality was better.'
                              : ' — Air quality is expected to be better.',
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    rec.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
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

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.isSatellite = true});
  final Widget child;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: isSatellite
            ? const Color(0xFF0F172A).withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.88),
        border: Border.all(
          color: isSatellite
              ? Colors.white.withValues(alpha: 0.35)
              : const Color(0xFFCBD5E1),
          width: 1.1,
        ),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: child,
    );
  }
}

class _PillGrid extends StatelessWidget {
  const _PillGrid({
    required this.selectedKey,
    required this.onSelect,
    required this.isSatellite,
    required this.isHistory,
  });

  final String selectedKey;
  final ValueChanged<String> onSelect;
  final bool isSatellite;
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    // Single horizontal row of six pollutant pills.
    return Row(
      children: [
        for (var i = 0; i < kHomePollutantFields.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _PollutantPill(
              label: kHomePollutantFields[i].$2,
              selected: selectedKey == kHomePollutantFields[i].$1,
              activeColor: AqiChartTheme.pillColorFor(
                kHomePollutantFields[i].$1,
                isSatellite: isSatellite,
                isHistory: isHistory,
              ),
              isSatellite: isSatellite,
              onTap: () => onSelect(kHomePollutantFields[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _PollutantPill extends StatelessWidget {
  const _PollutantPill({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
    this.isSatellite = true,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final bool isSatellite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unselectedBg = isSatellite
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.88);
    final unselectedBorder = isSatellite
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFFCBD5E1);
    final unselectedText = isSatellite
        ? Colors.white70
        : const Color(0xFF334155);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? activeColor : unselectedBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.95)
                  : unselectedBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : (isSatellite
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : unselectedText,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.isHistory,
    required this.onChanged,
    required this.accentColor,
    this.isSatellite = true,
  });

  final bool isHistory;
  final ValueChanged<bool> onChanged;
  final Color accentColor;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    final toggleBg = isSatellite
        ? const Color(0xFF0F172A).withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.88);
    final toggleBorder = isSatellite
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFFCBD5E1);

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: toggleBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: toggleBorder,
          width: 1.1,
        ),
        boxShadow: isSatellite
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSeg(
              label: 'History',
              selected: isHistory,
              accentColor: accentColor,
              isSatellite: isSatellite,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ModeSeg(
              label: 'Prediction',
              selected: !isHistory,
              accentColor: accentColor,
              isSatellite: isSatellite,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSeg extends StatelessWidget {
  const _ModeSeg({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    this.isSatellite = true,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final bool isSatellite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHist = label == 'History';
    final icon = isHist ? Icons.history_rounded : Icons.show_chart_rounded;
    final fgColor = selected
        ? Colors.white
        : (isSatellite ? Colors.white70 : const Color(0xFF475569));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: selected ? accentColor : Colors.transparent,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16.5, color: fgColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: fgColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowFooter extends StatelessWidget {
  const _WindowFooter({required this.isHistory, this.isSatellite = true});
  final bool isHistory;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    final color = isSatellite
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF94A3B8);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isHistory ? 'Last 6' : 'Next 6',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSatellite
                  ? Colors.white.withValues(alpha: 0.5)
                  : const Color(0xFFCBD5E1),
            ),
          ),
        ),
        Text(
          'Hours',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFF64748B),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: Color(0xFF14B8A6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Column + smooth line — exact solid bars, line and markers from Showcase designs.
class _PollutantComboChart extends StatelessWidget {
  const _PollutantComboChart({
    required this.samples,
    required this.pollutantKey,
    required this.pollutantLabel,
    required this.unit,
    required this.theme,
    this.isSatellite = true,
  });

  final List<AqiHourSample> samples;
  final String pollutantKey;
  final String pollutantLabel;
  final String unit;
  final AqiChartTheme theme;
  final bool isSatellite;

  Color get _lineColor => theme.lineColor;

  static ({double maxY, double interval}) _scale(double maxV) {
    if (maxV <= 0) return (maxY: 10, interval: 2);
    // Provide generous headroom so actual numerical values above data points never clip
    final padded = maxV * 1.30;
    final magnitude = math.pow(10, (math.log(padded) / math.ln10).floor());
    final norm = padded / magnitude;
    final nice = norm <= 1
        ? 1.0
        : norm <= 2
            ? 2.0
            : norm <= 5
                ? 5.0
                : 10.0;
    final maxY = nice * magnitude;
    return (maxY: maxY.toDouble(), interval: (maxY / 5).toDouble());
  }

  static String _fmtValue(double v) {
    if (v.abs() >= 100) return v.round().toString();
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final values = <double>[];
    final labels = <String>[];
    final hourFmt = DateFormat('HH');

    for (final s in samples) {
      final v = s.valueOf(pollutantKey);
      if (v == null) continue;
      values.add(v);
      labels.add(hourFmt.format(s.time));
    }

    if (values.isEmpty) {
      return const _MessagePane(
        message: 'No readings for this pollutant in the selected window.',
      );
    }

    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    final scale = _scale(maxV);
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    final n = values.length;
    final maxX = (n - 1).clamp(1, 100).toDouble();
    const leftReserve = 32.0;
    const bottomReserve = 22.0;
    final barWidth = n <= 6 ? 34.0 : (n <= 12 ? 18.0 : 10.0);

    final axisTextColor = isSatellite
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF334155);

    Widget axisTitleLeft(double v) {
      if (v < -0.01 || v > scale.maxY + 0.01) return const SizedBox.shrink();
      final onStep =
          (v / scale.interval - (v / scale.interval).round()).abs() < 0.05;
      if (!onStep && v > 0.01 && (v - scale.maxY).abs() > 0.01) {
        return const SizedBox.shrink();
      }
      return Text(
        _fmtValue(v),
        style: TextStyle(
          fontSize: 11,
          color: axisTextColor,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    Widget axisTitleBottom(double v) {
      final i = v.round();
      if (i < 0 || i >= labels.length) return const SizedBox.shrink();
      if (labels.length > 10 && i % 2 != 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          labels[i],
          style: TextStyle(
            fontSize: 11,
            color: axisTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final barGroups = [
      for (var i = 0; i < values.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: values[i],
              width: barWidth,
              borderRadius: BorderRadius.circular(16),
              // Exact solid bar fill from the referenced designs. No gradients.
              color: theme.barColor,
            ),
          ],
        ),
    ];

    final valueTextColor = isSatellite
        ? Colors.white
        : const Color(0xFF0F172A);

    return Stack(
      children: [
        BarChart(
          BarChartData(
            minY: 0,
            maxY: scale.maxY,
            alignment: BarChartAlignment.spaceAround,
            groupsSpace: n <= 6 ? 10 : 6,
            barTouchData: BarTouchData(enabled: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: scale.interval,
              getDrawingHorizontalLine: (_) => FlLine(
                color: (isSatellite ? Colors.white : const Color(0xFF94A3B8))
                    .withValues(alpha: 0.22),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: leftReserve,
                  interval: scale.interval,
                  getTitlesWidget: (v, _) => axisTitleLeft(v),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: bottomReserve,
                  getTitlesWidget: (v, _) => axisTitleBottom(v),
                ),
              ),
            ),
            barGroups: barGroups,
          ),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        ),
        LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: 0,
            maxY: scale.maxY,
            clipData: const FlClipData.none(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: leftReserve,
                  getTitlesWidget: (v, m) => const SizedBox.shrink(),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: bottomReserve,
                  getTitlesWidget: (v, m) => const SizedBox.shrink(),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              enabled: true,
              handleBuiltInTouches: true,
              getTouchedSpotIndicator: (bar, indexes) => indexes
                  .map(
                    (i) => TouchedSpotIndicatorData(
                      FlLine(
                        color: _lineColor.withValues(alpha: 0.35),
                        strokeWidth: 1.2,
                        dashArray: const [3, 3],
                      ),
                      FlDotData(
                        getDotPainter: (s, p, b, idx) => FlDotCirclePainter(
                          radius: 6.5,
                          color: Colors.white,
                          strokeWidth: 2.6,
                          strokeColor: theme.dotStrokeColor,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) =>
                    Color.lerp(theme.barColor, const Color(0xFF0F172A), 0.45)!,
                tooltipBorderRadius: BorderRadius.circular(10),
                tooltipPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                getTooltipItems: (touched) => touched.map((t) {
                  return LineTooltipItem(
                    _fmtValue(t.y),
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    children: [
                      TextSpan(
                        text: '\n$pollutantLabel · $unit',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.24,
                preventCurveOverShooting: true,
                // Matching graph line color from the reference designs
                color: _lineColor,
                barWidth: 2.8,
                isStrokeCapRound: true,
                shadow: Shadow(
                  color: _lineColor.withValues(alpha: 0.35),
                  blurRadius: 4,
                ),
                dotData: FlDotData(
                  show: true,
                  // Matching white circular dots with actual numerical value displayed above every data point
                  getDotPainter: (spot, pct, bar, index) => _ValueLabelDotPainter(
                    radius: 4.6,
                    color: Colors.white,
                    strokeWidth: 2.4,
                    strokeColor: theme.dotStrokeColor,
                    textColor: valueTextColor,
                  ),
                ),
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}

class _ValueLabelDotPainter extends FlDotCirclePainter {
  _ValueLabelDotPainter({
    required super.radius,
    required super.color,
    required super.strokeWidth,
    required super.strokeColor,
    required this.textColor,
  });

  final Color textColor;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    super.draw(canvas, spot, offsetInCanvas);

    final text = _PollutantComboChart._fmtValue(spot.y);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        offsetInCanvas.dx - textPainter.width / 2,
        offsetInCanvas.dy - textPainter.height - 7,
      ),
    );
  }
}
