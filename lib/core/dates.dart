import 'package:intl/intl.dart';

class Dates {
  Dates._();

  static const monthNamesFr = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  static int nowMillis() => DateTime.now().millisecondsSinceEpoch;

  /// Local business date used for indexing and daily reports.
  static String businessDate([DateTime? at]) {
    final d = at ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  static DateTime addMonths(DateTime d, int months) =>
      DateTime(d.year, d.month + months, 1);

  static int millisAtStartOfDay(DateTime d) =>
      startOfDay(d).millisecondsSinceEpoch;

  static int millisAtEndOfDay(DateTime d) => endOfDay(d).millisecondsSinceEpoch;

  static String formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  static String formatDateShort(DateTime d) => DateFormat('dd/MM').format(d);

  static String formatTime(DateTime d) => DateFormat('HH:mm').format(d);

  static String formatDateTime(DateTime d) =>
      '${formatDate(d)} ${formatTime(d)}';

  static String formatDateLong(DateTime d, {bool arabic = false}) {
    if (arabic) {
      return '${d.day} ${monthNamesAr[d.month - 1]} ${d.year}';
    }
    return '${d.day} ${monthNamesFr[d.month - 1]} ${d.year}';
  }

  static const monthNamesAr = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'ماي',
    'يونيو',
    'يوليوز',
    'غشت',
    'شتنبر',
    'أكتوبر',
    'نونبر',
    'دجنبر',
  ];

  static DateTime? tryParseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final date = DateTime(y, m, d);
    if (date.year != y || date.month != m || date.day != d) return null;
    return date;
  }

  static int? daysUntil(String? expiryDate, [DateTime? now]) {
    final date = tryParseDate(expiryDate);
    if (date == null) return null;
    final today = startOfDay(now ?? DateTime.now());
    return date.difference(today).inDays;
  }
}
