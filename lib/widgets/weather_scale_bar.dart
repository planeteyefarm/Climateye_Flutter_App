import 'package:flutter/material.dart';
import 'weather_mode_bar.dart';

class WeatherScaleBar extends StatelessWidget {
  const WeatherScaleBar({
    super.key,
    required this.mode,
    this.rainForecastMode = true,
    this.onToggleRainForecast,
    this.loading = false,
  });

  final WeatherOverlayMode mode;
  final bool rainForecastMode;
  final ValueChanged<bool>? onToggleRainForecast;
  final bool loading;

  static const _tempLabels = [-20, -10, 0, 10, 20, 30, 40];
  static const _rainLabels = [0.0, 1.5, 3.0, 7.0, 10.0, 20.0, 30.0];
  static const _windLabels = [0, 10, 20, 35, 55, 70, 100];

  @override
  Widget build(BuildContext context) {
    if (mode == WeatherOverlayMode.none) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 450;
        return Container(
          constraints: const BoxConstraints(maxWidth: 580, minWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(10, 14, 39, 0.85),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.3),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mode == WeatherOverlayMode.rain) ...[
                _buildRainModeToggle(),
                const SizedBox(width: 8),
              ],
              Text(
                _getUnitText(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2E8F0),
                  shadows: [
                    Shadow(color: Colors.black87, blurRadius: 4),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 18,
                        decoration: BoxDecoration(
                          gradient: _getGradient(),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.28),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      _buildLabels(compact),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRainModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.9),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(label: 'Recent', active: !rainForecastMode, value: false),
          _toggleBtn(label: 'Forecast', active: rainForecastMode, value: true),
        ],
      ),
    );
  }

  Widget _toggleBtn({required String label, required bool active, required bool value}) {
    return InkWell(
      onTap: () => onToggleRainForecast?.call(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF145A82) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : const Color(0xFF3A2F45),
          ),
        ),
      ),
    );
  }

  String _getUnitText() {
    switch (mode) {
      case WeatherOverlayMode.temp:
        return '°C · now';
      case WeatherOverlayMode.rain:
        return 'mm/3h';
      case WeatherOverlayMode.wind:
        return 'km/h';
      case WeatherOverlayMode.none:
        return '';
    }
  }

  LinearGradient _getGradient() {
    switch (mode) {
      case WeatherOverlayMode.temp:
        return const LinearGradient(
          colors: [
            Color(0xFF122896),
            Color(0xFF2464D2),
            Color(0xFF30AAD6),
            Color(0xFF28C8C3),
            Color(0xFF37CD5F),
            Color(0xFF96DC2D),
            Color(0xFFEBE128),
            Color(0xFFF5B91E),
            Color(0xFFF0821C),
            Color(0xFFE6501C),
            Color(0xFF91261E),
          ],
        );
      case WeatherOverlayMode.rain:
        return const LinearGradient(
          colors: [
            Color(0xFF145A82),
            Color(0xFF30AAC0),
            Color(0xFF24A878),
            Color(0xFF48C440),
            Color(0xFFC8D230),
            Color(0xFFECA024),
            Color(0xFFC430A0),
          ],
        );
      case WeatherOverlayMode.wind:
        return const LinearGradient(
          colors: [
            Color(0xFF7A2E9E),
            Color(0xFF3A4ACC),
            Color(0xFF20BAD6),
            Color(0xFF36C460),
            Color(0xFFE6D630),
            Color(0xFFEC8420),
            Color(0xFFC6242A),
          ],
        );
      case WeatherOverlayMode.none:
        return const LinearGradient(colors: [Colors.transparent, Colors.transparent]);
    }
  }

  Widget _buildLabels(bool compact) {
    switch (mode) {
      case WeatherOverlayMode.temp:
        final labels = compact ? [-20, 0, 20, 40] : _tempLabels;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels.map((v) => _labelSpan('$v')).toList(),
        );
      case WeatherOverlayMode.rain:
        final labels = compact ? [0.0, 7.0, 30.0] : _rainLabels;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels.map((v) => _labelSpan(v == v.roundToDouble() ? '${v.toInt()}' : '$v')).toList(),
        );
      case WeatherOverlayMode.wind:
        final labels = compact ? [0, 35, 100] : _windLabels;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels.map((v) => _labelSpan('$v')).toList(),
        );
      case WeatherOverlayMode.none:
        return const SizedBox.shrink();
    }
  }

  Widget _labelSpan(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1024),
          shadows: [
            Shadow(color: Color.fromRGBO(255, 255, 255, 0.85), blurRadius: 3),
          ],
        ),
      ),
    );
  }
}
