import 'package:intl/intl.dart';

/// Formattazione di date e numeri in italiano.

String fmtDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String fmtDateTime(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d);

String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);

String fmtLongDate(DateTime d) => DateFormat('EEEE d MMMM y', 'it_IT').format(d);

String fmtTemp(double value) =>
    '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} °C';

String fmtQty(double? value, [String? unit]) {
  if (value == null) return '';
  final v = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return unit == null || unit.isEmpty ? v : '$v $unit';
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String sanitizeFileName(String input) => input
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceFirst(RegExp(r'^_'), '')
    .replaceFirst(RegExp(r'_$'), '');
