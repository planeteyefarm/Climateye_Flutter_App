import 'package:flutter/material.dart';
import '../models/weather.dart';

class ForecastTimelineStrip extends StatelessWidget {
  const ForecastTimelineStrip({
    super.key,
    required this.dailyRecords,
    required this.selectedDate,
    required this.onSelectDate,
    this.loading = false,
  });

  final List<MonthlyWeatherDay> dailyRecords;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final bool loading;

  String _weekdayShort(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }

  String _formatTemp(double? temp) {
    if (temp == null) return '--°';
    return '${temp.toStringAsFixed(1)}°';
  }

  @override
  Widget build(BuildContext context) {
    if (dailyRecords.isEmpty && !loading) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Color.fromRGBO(12, 14, 24, 0.98),
        border: Border(
          top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.22), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.35),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: loading && dailyRecords.isEmpty
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF14B8A6),
                ),
              ),
            )
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: dailyRecords.length,
              itemBuilder: (context, index) {
                final day = dailyRecords[index];
                final d = day.date;
                if (d == null) return const SizedBox.shrink();

                final dayZero = DateTime(d.year, d.month, d.day);
                final isSelected = selectedDate != null &&
                    dayZero.year == selectedDate!.year &&
                    dayZero.month == selectedDate!.month &&
                    dayZero.day == selectedDate!.day;
                final isForecast = dayZero.isAfter(today);

                final label = '${_weekdayShort(d)} ${d.day}';

                return Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => onSelectDate(d),
                    child: Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color.fromRGBO(251, 146, 60, 0.28)
                            : Colors.transparent,
                        border: Border(
                          right: const BorderSide(
                            color: Color.fromRGBO(255, 255, 255, 0.16),
                            width: 1,
                          ),
                          top: isSelected
                              ? const BorderSide(color: Color(0xFFFB923C), width: 2)
                              : BorderSide.none,
                          bottom: isSelected
                              ? const BorderSide(color: Color(0xFFFB923C), width: 2)
                              : BorderSide.none,
                        ),
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? const Color(0xFFFFF7ED)
                                          : const Color(0xFFF3E8C8),
                                    ),
                                  ),
                                  if (isForecast) ...[
                                    const SizedBox(width: 2.5),
                                    Container(
                                      width: 4.5,
                                      height: 4.5,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF59E0B),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 1.5),
                              Text(
                                _formatTemp(day.tempMax),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? const Color(0xFFFFEDD5)
                                      : Colors.white,
                                ),
                              ),
                              Text(
                                _formatTemp(day.tempMin),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: Color.fromRGBO(243, 232, 200, 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
