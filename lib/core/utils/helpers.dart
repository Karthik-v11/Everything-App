import 'package:intl/intl.dart';

/// Pure, stateless helper functions.
///
/// DO NOT MODIFY.
class Helpers {
  const Helpers._();

  /// [greeting] is the Dashboard salutation — "Good Morning" / "Good Afternoon"
  /// / "Good Evening" based on [at] (defaults to now).
  static String greeting({DateTime? at}) {
    final hour = (at ?? DateTime.now()).hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ── Money ──────────────────────────────────────────────────────────────────
  //
  // Money is stored throughout the app as an **integer number of minor units**
  // (paise / cents), never as a double. Binary floating point cannot represent
  // 0.1 exactly, so summing a long sequence of `double` expenses accumulates
  // error — which would break the finance summary totals. Convert at the edges
  // only, using the two functions below.

  /// [toMinorUnits] converts a user-entered major-unit amount (₹150.75) into the
  /// integer minor units that get stored (15075).
  static int toMinorUnits(double major) => (major * 100).round();

  /// [toMajorUnits] converts stored minor units back to a display double.
  static double toMajorUnits(int minor) => minor / 100;

  /// [formatMoney] renders stored minor units for display: `₹15,000`.
  ///
  /// [compact] drops the decimals, which is what the summary cards want.
  static String formatMoney(
    int minorUnits, {
    String symbol = '₹',
    String locale = 'en_IN',
    bool compact = false,
  }) {
    final format = NumberFormat.currency(
      locale: locale,
      symbol: symbol,
      decimalDigits: compact ? 0 : 2,
    );
    return format.format(toMajorUnits(minorUnits));
  }

  /// [parseMoney] reads a user-typed amount into minor units, tolerating
  /// grouping separators and a leading symbol. Returns null when unparseable.
  static int? parseMoney(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final value = double.tryParse(cleaned);
    return value == null ? null : toMinorUnits(value);
  }

  /// [percentOf] is `part / whole` as a 0–100 percentage, guarding the
  /// divide-by-zero that an unset budget would otherwise cause.
  static double percentOf(num part, num whole) =>
      whole <= 0 ? 0 : (part / whole) * 100;
}
