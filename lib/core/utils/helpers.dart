import 'package:intl/intl.dart';

/// [Season] is the time of year the daily briefing is told about.
///
/// The app is India-first — news defaults to `country: in` and the weather to
/// Bengaluru — so the four-season Western calendar is simply wrong here: the
/// Indian Meteorological Department's seasons are what a reader in Bengaluru
/// recognises, and a briefing that calls August "summer" is a briefing written
/// for somewhere else.
enum Season {
  summer,
  monsoon,
  postMonsoon,
  winter;

  /// [label] is the season in the words the briefing prompt uses.
  String get label => switch (this) {
        Season.summer => 'summer',
        Season.monsoon => 'monsoon',
        Season.postMonsoon => 'post-monsoon',
        Season.winter => 'winter',
      };
}

/// Pure, stateless helper functions.
///
/// DO NOT MODIFY.
class Helpers {
  const Helpers._();

  /// Built once: [parseMoney] runs on every keystroke of an amount field.
  static final RegExp _nonNumeric = RegExp(r'[^0-9.\-]');

  /// [greeting] is the Dashboard salutation — "Good Morning" / "Good Afternoon"
  /// / "Good Evening" based on [at] (defaults to now).
  static String greeting({DateTime? at}) {
    final hour = (at ?? DateTime.now()).hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  /// [seasonOf] maps a date onto its [Season] by month (IMD boundaries).
  static Season seasonOf(DateTime date) => switch (date.month) {
        3 || 4 || 5 => Season.summer,
        6 || 7 || 8 || 9 => Season.monsoon,
        10 || 11 => Season.postMonsoon,
        _ => Season.winter,
      };

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
    final cleaned = input.replaceAll(_nonNumeric, '');
    final value = double.tryParse(cleaned);
    return value == null ? null : toMinorUnits(value);
  }

  /// [percentOf] is `part / whole` as a 0–100 percentage, guarding the
  /// divide-by-zero that an unset budget would otherwise cause.
  static double percentOf(num part, num whole) =>
      whole <= 0 ? 0 : (part / whole) * 100;
}
