import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/models/transaction.dart';

/// [ParsedTransactionIntent] is the assistant's reading of a line meant to log
/// money — "Spent 500 on food", "got 20000 salary" (Requirement 16.3).
///
/// Like [ParsedTaskIntent] it is the stable shape the AI layer returns, filled by
/// the rule-based parser now and by the model later. The amount is the field it
/// exists to find: without one there is nothing to record, so an amount-less line
/// scores below the threshold and the sheet asks how much.
class ParsedTransactionIntent {
  ParsedTransactionIntent({
    required this.title,
    required this.amountMinor,
    required this.type,
    required this.category,
    required this.date,
    required this.confidence,
  });

  final String title;

  /// The amount in minor units (paise), never negative — direction is [type], as
  /// everywhere else in the app (see [Transaction]). Zero when none was found.
  final int amountMinor;
  final TransactionType type;
  final String category;
  final DateTime date;

  /// 0–1 confidence this was a spend/earning worth recording. An amount is the
  /// deciding evidence; a spend verb ("spent", "paid") and a recognisable
  /// category corroborate it.
  final double confidence;

  bool get hasAmount => amountMinor > 0;

  /// [isConfidentAt] gates automatic creation against the user's threshold
  /// (Requirement 25.3). An amount is required at every threshold: an expense
  /// with no amount is not a transaction, however confident the parse.
  bool isConfidentAt(double threshold) => confidence >= threshold && hasAmount;

  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);

  /// [ParsedTransactionIntent.parse] reads [input] into a transaction intent.
  ///
  /// The category comes from [inferTransactionCategory] — the same keyword lexicon
  /// the transaction sheet uses (plan §5), so "Swiggy" is Food from the assistant
  /// exactly as it is from the sheet. [now] anchors "today"/"yesterday" and is
  /// injectable for testing.
  factory ParsedTransactionIntent.parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();

    final amount = _amountOf(input);
    final type = _typeOf(input);

    final category =
        inferTransactionCategory(input) ?? _defaultCategory(type);

    final date = _dateOf(input, reference);
    final title = _titleOf(input);

    // No amount means nothing to record — score it low so the sheet asks. With an
    // amount the line is already usable; a spend/earn verb and a matched category
    // are corroboration that lift it from "a number" to "a transaction".
    final double confidence;
    if (amount == null) {
      confidence = 0.2;
    } else {
      var score = 0.7;
      if (_verbPattern.hasMatch(input.toLowerCase())) score += 0.15;
      if (inferTransactionCategory(input) != null) score += 0.1;
      confidence = score > 1 ? 1 : score;
    }

    return ParsedTransactionIntent(
      title: title,
      amountMinor: amount ?? 0,
      type: type,
      category: category,
      date: date,
      confidence: confidence,
    );
  }

  /// [toTransaction] assembles the transaction to save against [accountId], which
  /// the caller supplies from the user's accounts — the parser has no way to know
  /// which account a spend came from, and the service requires one.
  ///
  /// An untitled line is named after its category, matching the transaction
  /// sheet: the service rejects a blank title, and "Food" is a better answer than
  /// making the user type it.
  Transaction toTransaction({required String accountId}) {
    final trimmed = title.trim();

    return Transaction(
      id: '',
      title: trimmed.isEmpty ? category : trimmed,
      amountMinor: amountMinor,
      date: date,
      type: type,
      category: category,
      accountId: accountId,
      createdAt: DateTime.now(),
    );
  }

  static String _defaultCategory(TransactionType type) =>
      type == TransactionType.income ? 'Salary' : kDefaultTransactionCategory;

  // ── Amount ───────────────────────────────────────────────────────────────

  /// A number, optionally led by a currency marker and trailed by a magnitude
  /// suffix: `₹500`, `rs 1,200`, `2k`, `1.5 lakh`.
  static final RegExp _amountPattern = RegExp(
    r'(₹|rs\.?|inr|\$)?\s?(\d[\d,]*(?:\.\d+)?)\s?(k|lac|lakh|l)?\b',
    caseSensitive: false,
  );

  /// [_amountOf] is the amount in minor units, or null when the line has no
  /// number.
  ///
  /// When several numbers appear ("2 coffees for 400"), a number wearing a
  /// currency marker or a magnitude suffix wins — it is unambiguously the money —
  /// and otherwise the largest is taken, since a count ("2") is almost always
  /// smaller than the amount it counts toward.
  static int? _amountOf(String input) {
    ({int minor, bool marked})? best;

    for (final match in _amountPattern.allMatches(input)) {
      final digits = match.group(2)!.replaceAll(',', '');
      final value = double.tryParse(digits);
      if (value == null) continue;

      final suffix = match.group(3)?.toLowerCase();
      final multiplier = switch (suffix) {
        'k' => 1000,
        'l' || 'lac' || 'lakh' => 100000,
        _ => 1,
      };
      final marked = match.group(1) != null || suffix != null;
      final minor = (value * multiplier * 100).round();

      // A marked amount is decisive; keep the first one seen. Otherwise track the
      // largest unmarked number as the fallback.
      if (best == null ||
          (marked && !best.marked) ||
          (marked == best.marked && minor > best.minor)) {
        best = (minor: minor, marked: marked);
      }
    }

    return best?.minor;
  }

  // ── Type ─────────────────────────────────────────────────────────────────

  static final RegExp _incomePattern = RegExp(
    r'\b(received|credited|earned|got\s+paid|salary|income|refund|'
    r'cashback|deposited|reimburs\w*)\b',
    caseSensitive: false,
  );

  static final RegExp _investmentPattern = RegExp(
    r'\b(invested|investing|investment|sip)\b',
    caseSensitive: false,
  );

  /// Any verb that marks the line as a deliberate money entry, income or expense —
  /// used only to raise confidence, not to classify.
  static final RegExp _verbPattern = RegExp(
    r'\b(spent|spend|paid|pay|bought|buy|purchased|received|credited|earned|'
    r'got|salary|invested|deposited|refund|cashback)\b',
    caseSensitive: false,
  );

  static TransactionType _typeOf(String input) {
    if (_investmentPattern.hasMatch(input)) return TransactionType.investment;
    if (_incomePattern.hasMatch(input)) return TransactionType.income;
    return TransactionType.expense;
  }

  // ── Date ─────────────────────────────────────────────────────────────────

  static final RegExp _relativeDayPattern = RegExp(
    r'\b(today|yesterday|tomorrow)\b',
    caseSensitive: false,
  );

  /// [_dateOf] keeps a transaction on the day it happened — most are logged the
  /// same day, but "yesterday" is common enough to honour. Everything else is
  /// today. The time of day is kept from [reference] so two same-day entries keep
  /// their order.
  static DateTime _dateOf(String input, DateTime reference) {
    final match = _relativeDayPattern.firstMatch(input);
    if (match == null) return reference;

    final shift = switch (match.group(1)!.toLowerCase()) {
      'yesterday' => -1,
      'tomorrow' => 1,
      _ => 0,
    };
    if (shift == 0) return reference;

    return reference.add(Duration(days: shift));
  }

  // ── Title ──────────────────────────────────────────────────────────────────

  /// The filler stripped off the front of a title: the money itself, the verbs
  /// that introduce it, currency words, and the connectors ("on", "for") that sit
  /// between the verb and the thing bought. What survives is the description.
  static final RegExp _titleNoise = RegExp(
    r'(₹|rs\.?|inr|\$)?\s?\d[\d,]*(?:\.\d+)?\s?(k|lac|lakh|l)?\b'
    r'|\b(spent|spend|paid|pay|bought|buy|purchased|purchase|received|credited|'
    r'earned|got|invested|investing|deposited|refund|cashback|reimburs\w*|'
    r'today|yesterday|tomorrow|rupees|rupee)\b'
    r'|\b(on|for|of|to|from|at|in|the|a|an|my)\b',
    caseSensitive: false,
  );

  static final RegExp _whitespace = RegExp(r'\s+');

  static String _titleOf(String input) => input
      .replaceAll(_titleNoise, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();
}
