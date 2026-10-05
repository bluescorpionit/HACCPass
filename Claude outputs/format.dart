import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final DateFormat _date = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateShort = DateFormat('dd/MM/yy');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  static String date(DateTime? v) => v == null ? '-' : _date.format(v);
  static String dateShort(DateTime? v) => v == null ? '-' : _dateShort.format(v);
  static String time(DateTime? v) => v == null ? '-' : _time.format(v);
  static String dateTime(DateTime? v) => v == null ? '-' : _dateTime.format(v);

  static String temp(num? v) {
    if (v == null) return '-';
    return '${v.toStringAsFixed(1).replaceAll('.', ',')} °C';
  }

  static String num1(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
  }

  /// "Domenica 4 ottobre"
  static String longToday(DateTime v) {
    final s = DateFormat('EEEE d MMMM', 'it_IT').format(v);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  static String monthYear(DateTime v) =>
      DateFormat('MMMM yyyy', 'it_IT').format(v);

  static double? parseNumber(String? text) {
    if (text == null) return null;
    final cleaned = text.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static DateTime startOfDay(DateTime v) => DateTime(v.year, v.month, v.day);

  static DateTime endOfDay(DateTime v) =>
      DateTime(v.year, v.month, v.day).add(const Duration(days: 1));

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Dà un'espressione tipo "tra 3 giorni" / "2 giorni fa" / "oggi".
  static String relativeDays(DateTime target, {DateTime? now}) {
    final n = startOfDay(now ?? DateTime.now());
    final t = startOfDay(target);
    final d = t.difference(n).inDays;
    if (d == 0) return 'oggi';
    if (d == 1) return 'domani';
    if (d == -1) return 'ieri';
    if (d > 0) return 'tra $d giorni';
    return '${-d} giorni fa';
  }
}
