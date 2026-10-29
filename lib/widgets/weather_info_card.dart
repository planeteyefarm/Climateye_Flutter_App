import 'package:flutter/material.dart';
import '../models/weather.dart';

class WeatherInfoCard extends StatefulWidget {
  const WeatherInfoCard({
    super.key,
    required this.weather,
    required this.monthlyResponse,
    required this.searchWidget,
    this.loading = false,
    this.error,
    this.onRefresh,
    this.compact = false,
    this.maxWidth = 340,
  });

  final WeatherSummary? weather;
  final MonthlyWeatherResponse? monthlyResponse;
  final Widget searchWidget;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;
  final bool compact;
  final double maxWidth;

  @override
  State<WeatherInfoCard> createState() => _WeatherInfoCardState();
}

class _WeatherInfoCardState extends State<WeatherInfoCard> {
  late bool _minimized = widget.compact;

  String _formatTemp(double? temp) {
    if (temp == null) return '--°';
    return '${temp.toStringAsFixed(1)}°';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.weather;
    final m = widget.monthlyResponse;
    final sum = m?.summary ?? const {};

    return Container(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(10, 14, 39, 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color.fromRGBO(20, 184, 166, 0.35)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.45),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top search row
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Row(
              children: [
                Expanded(child: widget.searchWidget),
                if (widget.compact) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      _minimized
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: Colors.white70,
                      size: 20,
                    ),
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _minimized = !_minimized),
                  ),
                ],
              ],
            ),
          ),

          if (!_minimized) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.loading && w == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Loading temperature...',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color.fromRGBO(255, 255, 255, 0.78),
                        ),
                      ),
                    )
                  else if (widget.error != null && w == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        widget.error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFF87171),
                        ),
                      ),
                    )
                  else ...[
                    // Large Temperature & Side details
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTemp(w?.temperature),
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Feels like ${_formatTemp(w?.feelsLike)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color.fromRGBO(255, 255, 255, 0.88),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'High ${_formatTemp(w?.tempMax)} · Low ${_formatTemp(w?.tempMin)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color.fromRGBO(255, 255, 255, 0.75),
                                ),
                              ),
                              if (w?.condition != null && w!.condition!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  w.condition!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF5EEAD4),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Month section label
                    Text(
                      m != null
                          ? 'MONTH · ${m.month}/${m.year}'
                          : 'MONTH · ${DateTime.now().month}/${DateTime.now().year}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.05,
                        color: Color.fromRGBO(255, 255, 255, 0.62),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Badges row
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildBadge('Sunny', sum['sunny'] ?? 0),
                        _buildBadge('Partly cloudy', sum['partly-cloudy'] ?? 0),
                        _buildBadge('Cloudy', sum['cloudy'] ?? 0),
                        _buildBadge('Rainy', sum['rainy'] ?? 0),
                        _buildBadge('Snowy', sum['snowy'] ?? 0),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color.fromRGBO(255, 255, 255, 0.12),
          width: 0.8,
        ),
      ),
      child: Text(
        '$label $count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color.fromRGBO(255, 255, 255, 0.9),
        ),
      ),
    );
  }
}
