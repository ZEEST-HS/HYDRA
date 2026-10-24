import 'package:flutter/material.dart';

import '../../core/dates.dart';

/// Opens a localized date picker and returns an ISO `yyyy-MM-dd` date.
///
/// Used for expiry dates so the whole app stores them the same way.
Future<String?> pickIsoDate(
  BuildContext context, {
  String? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final now = DateTime.now();
  final initialDate = Dates.tryParseDate(initial) ?? now;
  final first = firstDate ?? DateTime(now.year - 10);
  final last = lastDate ?? DateTime(now.year + 25);
  final picked = await showDatePicker(
    context: context,
    initialDate: initialDate.isBefore(first)
        ? first
        : (initialDate.isAfter(last) ? last : initialDate),
    firstDate: first,
    lastDate: last,
  );
  return picked == null ? null : Dates.businessDate(picked);
}
