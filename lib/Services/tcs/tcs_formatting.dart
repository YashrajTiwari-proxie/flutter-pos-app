// Formatting/generation helpers the TCS calls need — every value the TCS
// receives has a strict, contractual format (see convex/lib/tcsXml.ts's
// validators on the fiscal branch for the exact rules to match):
//
// - Swedish decimal-comma amounts, e.g. "116,26" — never dot-decimal.
// - 14-digit DateTime, "YYYYMMDDhhmmss" (seconds required).
// - 12-digit SequenceNumber.
// - UUID v4 RequestID (the `uuid` package is already a pubspec dependency).

import 'dart:math';

String _pad(int value, int width) => value.toString().padLeft(width, '0');

/// cents (e.g. 11626) -> "116,26". Integer-cent input only — the backend
/// compares amounts as integer cents too, so there's no float drift on
/// either side to reconcile.
String formatSwedishAmount(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  return '$sign$whole,${_pad(fraction, 2)}';
}

/// Current wall-clock time as the TCS's 14-digit `YYYYMMDDhhmmss` (seconds
/// included — the CCU's 12-digit format without seconds is rejected).
String nowDateTime14() {
  final d = DateTime.now();
  return '${d.year}${_pad(d.month, 2)}${_pad(d.day, 2)}'
      '${_pad(d.hour, 2)}${_pad(d.minute, 2)}${_pad(d.second, 2)}';
}

final _sequenceRandom = Random();

/// A random 12-digit receipt sequence number (TCS format).
String randomSequenceNumber() {
  final buffer = StringBuffer();
  for (var i = 0; i < 12; i++) {
    buffer.write(_sequenceRandom.nextInt(10));
  }
  return buffer.toString();
}

/// Splits a total (in cents) into {subtotalCents, vatCents} for a single VAT
/// band at [vatPercentBasisPoints] (e.g. 2500 for 25.00%), rounding to the
/// nearest cent — so `subtotalCents + vatCents == totalCents` always holds,
/// matching the backend's exact integer-cents VAT-math invariant
/// (`saleAmount == Σ(SubtotalAmount + Amount)`).
({int subtotalCents, int vatCents}) splitVat(
  int totalCents,
  int vatPercentBasisPoints,
) {
  final denominator = 10000 + vatPercentBasisPoints;
  final subtotalCents =
      (totalCents * 10000 + denominator ~/ 2) ~/ denominator;
  final vatCents = totalCents - subtotalCents;
  return (subtotalCents: subtotalCents, vatCents: vatCents);
}
