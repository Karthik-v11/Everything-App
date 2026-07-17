import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [TransactionType] is what a transaction does to the user's money
/// (Requirement 12.1).
///
/// [transfer] moves money between the user's own accounts. It is neither income
/// nor expense — counting it as either would double the month's totals, since the
/// same rupee shows up on both sides — so it is excluded from every summary
/// figure and from the budget.
enum TransactionType {
  income,
  expense,
  transfer,
  investment;

  String get label => name.capitalized;

  /// [isSpend] is true for the two types that take money out of an account.
  ///
  /// Only [expense] counts against the budget (Requirement 14.1): an investment
  /// is money moved, not money gone, and budgeting it as spending would tell a
  /// user who saved well that they overspent.
  bool get isSpend =>
      this == TransactionType.expense || this == TransactionType.investment;

  IconData get icon => switch (this) {
        TransactionType.income => Icons.south_west_rounded,
        TransactionType.expense => Icons.north_east_rounded,
        TransactionType.transfer => Icons.swap_horiz_rounded,
        TransactionType.investment => Icons.trending_up_rounded,
      };

  static TransactionType fromName(String? name) =>
      TransactionType.values.firstWhere(
        (value) => value.name == name,
        orElse: () => TransactionType.expense,
      );
}

/// [Transaction] is one financial record (Requirement 12.1).
///
/// [amountMinor] is a **non-negative integer count of minor units** (paise). The
/// direction of the money is [type], never the sign of the amount — a negative
/// expense and a positive income would otherwise mean the same thing, and every
/// summation would have to know which convention a row was written under.
///
/// It is an `int` rather than a `double` because Property 6 forbids precision
/// loss past two decimals and Property 7 sums an arbitrary sequence of these.
/// Binary floating point cannot promise either under repeated addition. Convert
/// at the UI edge with `Helpers.formatMoney` / `Helpers.parseMoney`.
class Transaction extends Equatable {
  const Transaction({
    required this.id,
    required this.title,
    required this.amountMinor,
    required this.date,
    required this.accountId,
    required this.createdAt,
    this.type = TransactionType.expense,
    this.category = kDefaultTransactionCategory,
    this.notes,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final int amountMinor;
  final DateTime date;
  final TransactionType type;

  /// The category name itself, not an id: Requirement 12.2 ends the list with
  /// "Custom", so the set is open and a lookup table would buy nothing.
  final String category;

  final String accountId;
  final String? notes;
  final List<String> tags;
  final DateTime createdAt;

  bool get isExpense => type == TransactionType.expense;

  bool get isIncome => type == TransactionType.income;

  /// [signedMinor] is the effect on the owning account's balance: income adds,
  /// expense and investment subtract.
  ///
  /// A transfer is 0 here. The schema gives a transaction one [accountId], so it
  /// records the leg that left an account, not the one that arrived — signing it
  /// would take money out of the source without ever putting it into the
  /// destination.
  int get signedMinor => switch (type) {
        TransactionType.income => amountMinor,
        TransactionType.expense || TransactionType.investment => -amountMinor,
        TransactionType.transfer => 0,
      };

  Color get color => categoryColor(category);

  /// [matches] is the in-memory search predicate: title, category, tags
  /// (Requirement 12.4).
  bool matches(String query) {
    if (query.isBlank) return true;
    return title.containsIgnoreCase(query) ||
        category.containsIgnoreCase(query) ||
        (notes?.containsIgnoreCase(query) ?? false) ||
        tags.any((tag) => tag.containsIgnoreCase(query));
  }

  factory Transaction.fromEntry(TransactionEntry entry) => Transaction(
        id: entry.id,
        title: entry.title,
        amountMinor: entry.amountMinor,
        date: entry.date,
        type: TransactionType.fromName(entry.type),
        category: entry.category,
        accountId: entry.accountId,
        notes: entry.notes,
        tags: _decodeTags(entry.tagsJson),
        createdAt: entry.createdAt,
      );

  TransactionsTableCompanion toCompanion() =>
      TransactionsTableCompanion.insert(
        id: id,
        title: title,
        amountMinor: amountMinor,
        date: date,
        type: type.name,
        category: category,
        accountId: accountId,
        notes: Value(notes),
        tagsJson: Value(jsonEncode(tags)),
        createdAt: createdAt,
      );

  Transaction copyWith({
    String? id,
    String? title,
    int? amountMinor,
    DateTime? date,
    TransactionType? type,
    String? category,
    String? accountId,
    String? notes,
    bool clearNotes = false,
    List<String>? tags,
    DateTime? createdAt,
  }) =>
      Transaction(
        id: id ?? this.id,
        title: title ?? this.title,
        amountMinor: amountMinor ?? this.amountMinor,
        date: date ?? this.date,
        type: type ?? this.type,
        category: category ?? this.category,
        accountId: accountId ?? this.accountId,
        notes: clearNotes ? null : (notes ?? this.notes),
        tags: tags ?? this.tags,
        createdAt: createdAt ?? this.createdAt,
      );

  static List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.cast<String>() : const [];
    } on FormatException {
      // A corrupt blob must not take the whole transaction list down with it.
      return const [];
    }
  }

  @override
  List<Object?> get props => [
        id,
        title,
        amountMinor,
        date,
        type,
        category,
        accountId,
        notes,
        tags,
        createdAt,
      ];
}

/// [kDefaultTransactionCategory] is what an uncategorised transaction falls into.
const String kDefaultTransactionCategory = 'Other';

/// [kTransactionCategories] is the starter set from Requirement 12.2.
///
/// It is a constant rather than a table: the user's own categories arrive simply
/// by being typed, since a transaction stores its category name directly.
const List<({String name, IconData icon})> kTransactionCategories = [
  (name: 'Food', icon: Icons.restaurant_rounded),
  (name: 'Travel', icon: Icons.flight_rounded),
  (name: 'Shopping', icon: Icons.shopping_bag_rounded),
  (name: 'Bills', icon: Icons.receipt_long_rounded),
  (name: 'Salary', icon: Icons.payments_rounded),
  (name: 'Investment', icon: Icons.trending_up_rounded),
  (name: 'Entertainment', icon: Icons.movie_rounded),
  (name: 'Healthcare', icon: Icons.favorite_rounded),
  (name: 'Education', icon: Icons.school_rounded),
  (name: kDefaultTransactionCategory, icon: Icons.category_rounded),
];

/// [kCategoryPalette] is the colour wheel the finance module draws categories
/// from. It extends [AppColors.chartPalette] — which is shorter than the starter
/// category set — with hues far enough from the base eight that no two of the
/// starter categories can be told apart only by squinting.
const List<Color> kCategoryPalette = <Color>[
  ...AppColors.chartPalette,
  Color(0xFF0EA5E9),
  Color(0xFF84CC16),
  Color(0xFF6366F1),
  Color(0xFFA16207),
  Color(0xFF00897B),
  Color(0xFF64748B),
];

/// [categoryColor] is the colour a category takes in **every** finance chart.
///
/// The same category must be the same colour in every chart or the legend stops
/// meaning anything.
///
/// A starter category takes the palette entry at its own index, so no two can
/// collide — a hash over a palette shorter than the category list cannot promise
/// that. A user's own category is hashed into the entries the starter set left
/// over, so it keeps its colour as other categories come and go.
Color categoryColor(String category) {
  final known = kTransactionCategories.indexWhere(
    (entry) => entry.name.toLowerCase() == category.toLowerCase(),
  );
  if (known >= 0) return kCategoryPalette[known % kCategoryPalette.length];

  final free = kCategoryPalette.length - kTransactionCategories.length;
  if (free <= 0) {
    return kCategoryPalette[_hashOf(category) % kCategoryPalette.length];
  }

  return kCategoryPalette[
      kTransactionCategories.length + _hashOf(category) % free];
}

/// [_hashOf] is FNV-1a over the lowercased name, kept positive.
int _hashOf(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// [categoryIcon] is the glyph for a known category, or a neutral one for a
/// category the user invented.
IconData categoryIcon(String category) {
  for (final known in kTransactionCategories) {
    if (known.name.toLowerCase() == category.toLowerCase()) return known.icon;
  }
  return Icons.category_rounded;
}

/// [_kCategoryKeywords] is the vocabulary [inferTransactionCategory] reads a
/// transaction's category out of. Keywords are lowercase and matched whole, so
/// "bar" does not fire on "barber".
///
/// Ordered by category; within a match, the *longest* keyword wins, which is what
/// lets "mutual fund" beat "fund" and "petrol pump" beat "pump".
const Map<String, List<String>> _kCategoryKeywords = {
  'Food': [
    'food', 'lunch', 'dinner', 'breakfast', 'brunch', 'meal', 'restaurant',
    'cafe', 'coffee', 'tea', 'snack', 'snacks', 'pizza', 'burger', 'biryani',
    'swiggy', 'zomato', 'starbucks', 'dominos', 'mcdonalds', 'kfc', 'bakery',
    'grocery', 'groceries', 'supermarket', 'blinkit', 'zepto', 'instamart',
    'bigbasket', 'dmart', 'milk', 'vegetables', 'fruits', 'canteen', 'juice',
  ],
  'Travel': [
    'travel', 'trip', 'uber', 'ola', 'rapido', 'cab', 'taxi', 'auto', 'flight',
    'flights', 'airline', 'indigo', 'train', 'irctc', 'railway', 'bus', 'metro',
    'petrol', 'diesel', 'fuel', 'toll', 'parking', 'hotel', 'airbnb', 'oyo',
    'ticket', 'tickets', 'visa', 'baggage', 'vacation', 'holiday',
  ],
  'Shopping': [
    'shopping', 'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa',
    'clothes', 'clothing', 'shirt', 'jeans', 'shoes', 'sneakers', 'watch',
    'mall', 'ikea', 'decathlon', 'furniture', 'gadget', 'headphones', 'laptop',
    'phone case', 'gift', 'gifts', 'accessories',
  ],
  'Bills': [
    'bill', 'bills', 'electricity', 'power bill', 'water bill', 'gas', 'lpg',
    'rent', 'maintenance', 'wifi', 'internet', 'broadband', 'jio', 'airtel',
    'vi', 'bsnl', 'recharge', 'postpaid', 'prepaid', 'dth', 'cable', 'emi',
    'loan', 'insurance', 'premium', 'tax', 'gst', 'fees', 'society',
  ],
  'Salary': [
    'salary', 'payroll', 'stipend', 'bonus', 'wages', 'incentive', 'freelance',
    'invoice', 'payout', 'commission', 'reimbursement', 'refund', 'cashback',
    'interest', 'dividend',
  ],
  'Investment': [
    'investment', 'invest', 'sip', 'mutual fund', 'mutual funds', 'stocks',
    'stock', 'shares', 'equity', 'zerodha', 'groww', 'upstox', 'nifty',
    'crypto', 'bitcoin', 'ethereum', 'gold', 'silver', 'fd', 'rd', 'ppf',
    'nps', 'bond', 'bonds', 'portfolio',
  ],
  'Entertainment': [
    'entertainment', 'movie', 'movies', 'cinema', 'pvr', 'inox', 'bookmyshow',
    'netflix', 'spotify', 'prime', 'hotstar', 'jiocinema', 'youtube', 'game',
    'games', 'gaming', 'steam', 'playstation', 'concert', 'event', 'party',
    'bar', 'pub', 'beer', 'wine', 'drinks', 'club', 'subscription',
  ],
  'Healthcare': [
    'healthcare', 'health', 'doctor', 'hospital', 'clinic', 'medicine',
    'medicines', 'medical', 'pharmacy', 'chemist', 'apollo', 'pharmeasy',
    '1mg', 'dentist', 'dental', 'checkup', 'lab', 'test', 'scan', 'therapy',
    'gym', 'fitness', 'yoga', 'supplements',
  ],
  'Education': [
    'education', 'course', 'courses', 'class', 'classes', 'tuition', 'school',
    'college', 'university', 'udemy', 'coursera', 'book', 'books', 'exam',
    'certification', 'workshop', 'training', 'stationery', 'notebook',
  ],
};

/// [inferTransactionCategory] reads a category out of what the user typed —
/// "Swiggy dinner" is Food, "Uber to office" is Travel — or returns null when the
/// text says nothing a category can be pinned on.
///
/// Keyword matching on word boundaries rather than a model: it runs on every
/// keystroke and must be right or silent — a wrong guess the user has to undo is
/// worse than no guess.
///
/// The caller decides what to do with a null and must not overrule a category the
/// user picked by hand.
String? inferTransactionCategory(String text) {
  if (text.isBlank) return null;

  final haystack = text.toLowerCase();

  String? best;
  var bestLength = 0;

  for (final entry in _kCategoryKeywords.entries) {
    for (final keyword in entry.value) {
      if (keyword.length <= bestLength) continue;
      if (!_containsWord(haystack, keyword)) continue;

      best = entry.key;
      bestLength = keyword.length;
    }
  }

  return best;
}

/// [_containsWord] is `contains` that will not match inside a longer word: an
/// expense titled "barber" is not a night at the bar.
bool _containsWord(String haystack, String needle) {
  var index = haystack.indexOf(needle);

  while (index >= 0) {
    final before = index == 0 ? null : haystack.codeUnitAt(index - 1);
    final afterIndex = index + needle.length;
    final after = afterIndex >= haystack.length
        ? null
        : haystack.codeUnitAt(afterIndex);

    if (!_isWordChar(before) && !_isWordChar(after)) return true;

    index = haystack.indexOf(needle, index + 1);
  }

  return false;
}

bool _isWordChar(int? unit) {
  if (unit == null) return false;
  final isDigit = unit >= 0x30 && unit <= 0x39;
  final isUpper = unit >= 0x41 && unit <= 0x5a;
  final isLower = unit >= 0x61 && unit <= 0x7a;
  return isDigit || isUpper || isLower;
}
