import 'package:flutter/material.dart';

enum WeatherOverlayMode {
  none,
  temp,
  rain,
  wind,
}

class WeatherModeBar extends StatelessWidget {
  const WeatherModeBar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.is3d,
    required this.onToggle3d,
    required this.isSatellite,
    required this.onToggleMap,
    this.compact = false,
  });

  final WeatherOverlayMode mode;
  final ValueChanged<WeatherOverlayMode> onModeChanged;
  final bool is3d;
  final VoidCallback onToggle3d;
  final bool isSatellite;
  final VoidCallback onToggleMap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 4,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(26, 31, 58, 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color.fromRGBO(20, 184, 166, 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.35),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            label: '3D',
            icon: Icons.view_in_ar_outlined,
            active: is3d,
            onTap: onToggle3d,
            tooltip: 'Toggle 3D View',
          ),
          SizedBox(width: compact ? 2.5 : 4),
          _buildButton(
            label: 'Temp',
            icon: Icons.thermostat_outlined,
            active: mode == WeatherOverlayMode.temp,
            onTap: () {
              onModeChanged(
                mode == WeatherOverlayMode.temp
                    ? WeatherOverlayMode.none
                    : WeatherOverlayMode.temp,
              );
            },
            tooltip: 'Temperature layer & forecast',
          ),
          SizedBox(width: compact ? 2.5 : 4),
          _buildButton(
            label: 'Rain',
            icon: Icons.water_drop_outlined,
            active: mode == WeatherOverlayMode.rain,
            onTap: () {
              onModeChanged(
                mode == WeatherOverlayMode.rain
                    ? WeatherOverlayMode.none
                    : WeatherOverlayMode.rain,
              );
            },
            tooltip: 'Rain & precipitation layer',
          ),
          SizedBox(width: compact ? 2.5 : 4),
          _buildButton(
            label: 'Wind',
            icon: Icons.air_outlined,
            active: mode == WeatherOverlayMode.wind,
            onTap: () {
              onModeChanged(
                mode == WeatherOverlayMode.wind
                    ? WeatherOverlayMode.none
                    : WeatherOverlayMode.wind,
              );
            },
            tooltip: 'Wind layer & vectors',
          ),
          SizedBox(width: compact ? 2.5 : 4),
          _buildButton(
            label: isSatellite ? 'Map' : 'Satellite',
            icon: isSatellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
            active: !isSatellite,
            onTap: onToggleMap,
            tooltip: isSatellite ? 'Switch to Map' : 'Switch to Satellite',
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    const tealColor = Color(0xFF14B8A6);
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 12,
              vertical: compact ? 4 : 8,
            ),
            decoration: BoxDecoration(
              color: active
                  ? const Color.fromRGBO(20, 184, 166, 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active ? tealColor : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (compact && label == '3D')
                  Text(
                    '3D',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active
                          ? tealColor
                          : const Color.fromRGBO(255, 255, 255, 0.85),
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: compact ? 15 : 17,
                    color: active
                        ? tealColor
                        : const Color.fromRGBO(255, 255, 255, 0.72),
                  ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? tealColor
                          : const Color.fromRGBO(255, 255, 255, 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
