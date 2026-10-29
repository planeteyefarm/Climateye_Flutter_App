import 'package:flutter/material.dart';
import '../models/aqi.dart';
import '../models/building.dart';
import '../models/weather.dart';
import '../theme.dart';
import 'glass.dart';

/// Available radius options in meters.
class RadiusOption {
  const RadiusOption({required this.meters, required this.label});
  final double meters;
  final String label;
}

const List<RadiusOption> kRadiusOptions = [
  RadiusOption(meters: 100, label: '100 m'),
  RadiusOption(meters: 2000, label: '2 km'),
  RadiusOption(meters: 5000, label: '5 km'),
  RadiusOption(meters: 10000, label: '10 km'),
];

String formatRadiusLabel(double meters) {
  if (meters >= 1000) {
    final km = meters / 1000;
    return km == km.roundToDouble() ? '${km.toInt()} km' : '${km.toStringAsFixed(1)} km';
  }
  return '${meters.toInt()} m';
}

/// Floating glass card displaying Near You radius analysis.
class NearYouPanel extends StatefulWidget {
  const NearYouPanel({
    super.key,
    required this.selectedRadius,
    required this.onSelectRadius,
    this.aqiRecord,
    this.weatherSummary,
    this.buildingCollection,
    this.loading = false,
    this.error,
    this.onClose,
    this.maxWidth,
    this.initiallyMinimized = false,
  });

  final double selectedRadius;
  final ValueChanged<double> onSelectRadius;
  final AqiRecord? aqiRecord;
  final WeatherSummary? weatherSummary;
  final BuildingCollection? buildingCollection;
  final bool loading;
  final String? error;
  final VoidCallback? onClose;
  final double? maxWidth;
  final bool initiallyMinimized;

  @override
  State<NearYouPanel> createState() => _NearYouPanelState();
}

class _NearYouPanelState extends State<NearYouPanel> {
  late bool _minimized = widget.initiallyMinimized;

  @override
  Widget build(BuildContext context) {
    final aqi = widget.aqiRecord?.aqi;
    final aqiCat = aqi != null ? aqiCategory(aqi) : null;
    final temp = widget.weatherSummary?.temperature;
    final condition = widget.weatherSummary?.condition;
    final bldgs = widget.buildingCollection;

    final effectiveMaxWidth = widget.maxWidth ?? 290.0;
    final isCompact = effectiveMaxWidth < 275.0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topRight,
      child: _minimized
          ? GlassPanel(
              radius: 20,
              opacity: 0.90,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 10 : 12,
                vertical: isCompact ? 6 : 8,
              ),
              child: InkWell(
                onTap: () => setState(() => _minimized = false),
                borderRadius: BorderRadius.circular(20),
                child: Tooltip(
                  message: 'Expand Near You panel',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isCompact ? 8 : 10,
                        height: isCompact ? 8 : 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Near you · ${formatRadiusLabel(widget.selectedRadius)}',
                        style: TextStyle(
                          fontSize: isCompact ? 11.5 : 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.cloudWhite,
                        ),
                      ),
                      if (bldgs != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          '(${bldgs.count}${bldgs.hasWarnings ? '+' : ''} bldgs)',
                          style: TextStyle(
                            fontSize: isCompact ? 10.5 : 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: isCompact ? 16 : 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: GlassPanel(
                radius: 18,
                opacity: 0.90,
                padding: isCompact
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                    : const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with title, collapse button, and optional close button
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _minimized = true),
                            borderRadius: BorderRadius.circular(6),
                            child: Row(
                              children: [
                                Text(
                                  'NEAR YOU',
                                  style: TextStyle(
                                    fontSize: isCompact ? 10.5 : 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.08,
                                    color: const Color(0xFFFDBA74),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.unfold_less,
                                  size: 13,
                                  color: Color(0xFFFDBA74),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _minimized = true),
                          borderRadius: BorderRadius.circular(12),
                          child: const Tooltip(
                            message: 'Collapse',
                            child: Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.keyboard_arrow_up,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        if (widget.onClose != null) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: widget.onClose,
                            borderRadius: BorderRadius.circular(12),
                            child: const Tooltip(
                              message: 'Close',
                              child: Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: isCompact ? 6 : 8),

                    // 4 Radius Selector Buttons
                    Row(
                      children: [
                        for (final opt in kRadiusOptions)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 1.5 : 2,
                              ),
                              child: _radiusButton(opt, compact: isCompact),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isCompact ? 6 : 8),

                    // Radius Title Label
                    Text(
                      'Within ${formatRadiusLabel(widget.selectedRadius)}',
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.cloudWhite,
                      ),
                    ),
                    SizedBox(height: isCompact ? 6 : 8),

                    // Loading / Error or Stats Grid
                    if (widget.loading) ...[
                      Container(
                        padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading nearby data…',
                              style: TextStyle(
                                fontSize: isCompact ? 11 : 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (widget.error != null) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: isCompact ? 4 : 6),
                        child: Text(
                          widget.error!,
                          style: TextStyle(
                            fontSize: isCompact ? 10.5 : 11.5,
                            color: const Color(0xFFFBBF24),
                          ),
                        ),
                      ),
                    ] else ...[
                      // 3-Column Stats Row: AQI, Temp, Buildings
                      Row(
                        children: [
                          Expanded(
                            child: _statBox(
                              label: 'AQI',
                              value: aqi != null ? aqi.round().toString() : '—',
                              valueColor: aqiCat?.color ?? AppColors.cloudWhite,
                              compact: isCompact,
                            ),
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                          Expanded(
                            child: _statBox(
                              label: 'TEMP',
                              value: temp != null ? '${temp.toStringAsFixed(1)}°' : '—',
                              valueColor: AppColors.cloudWhite,
                              compact: isCompact,
                            ),
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                          Expanded(
                            child: _statBox(
                              label: 'BUILDINGS',
                              value: bldgs != null
                                  ? '${bldgs.count}${bldgs.hasWarnings ? '+' : ''}'
                                  : '—',
                              valueColor: const Color(0xFF14B8A6),
                              compact: isCompact,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Weather condition label
                    if (condition != null && !widget.loading && widget.error == null) ...[
                      SizedBox(height: isCompact ? 4 : 6),
                      Text(
                        condition,
                        style: TextStyle(
                          fontSize: isCompact ? 10.5 : 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.cloudWhite,
                        ),
                      ),
                    ],

                    // Warning note for partial/truncated dataset
                    if (bldgs != null && !widget.loading && widget.error == null) ...[
                      if (bldgs.hasWarnings) ...[
                        SizedBox(height: isCompact ? 4 : 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 12, color: Color(0xFFFBBF24)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  bldgs.note ?? 'Partial coverage: dataset incomplete for this large radius',
                                  style: TextStyle(
                                    fontSize: isCompact ? 9 : 10,
                                    color: const Color(0xFFFDE68A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    SizedBox(height: isCompact ? 6 : 8),
                    // Footnote confirming point reading vs circle rule
                    Text(
                      'AQI and temperature at your location · Buildings inside the selected radius',
                      style: TextStyle(
                        fontSize: isCompact ? 8.5 : 9.5,
                        height: 1.25,
                        color: const Color(0x99A8BACB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _radiusButton(RadiusOption opt, {required bool compact}) {
    final isSelected = (opt.meters - widget.selectedRadius).abs() < 1;
    return InkWell(
      onTap: () => widget.onSelectRadius(opt.meters),
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: compact ? 3.5 : 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : Colors.white.withValues(alpha: 0.16),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            opt.label,
            style: TextStyle(
              fontSize: compact ? 10 : 10.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? const Color(0xFFFFF7ED) : AppColors.cloudWhite,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statBox({
    required String label,
    required String value,
    required Color valueColor,
    required bool compact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 4 : 6,
        horizontal: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 8.5 : 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.04,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          SizedBox(height: compact ? 1 : 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: compact ? 13.5 : 15,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
