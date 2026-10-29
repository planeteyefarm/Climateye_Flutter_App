import 'package:intl/intl.dart';

final DateFormat _ymd = DateFormat('yyyy-MM-dd');

String ymd(DateTime d) => _ymd.format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

/// Parses backend timestamps like "2026-10-08 12:00:00" or ISO strings.
DateTime? parseApiDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

String prettyDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
