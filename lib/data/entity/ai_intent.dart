import 'package:flutter/material.dart';

/// [AiIntent] is what the assistant thinks the user is trying to do with one line
/// of natural language (Requirement 16).
///
/// The rule-based parser classifies the input into one of these, which chooses
/// both the default mode of the AI sheet and the branch [AiService] runs. The
/// user can always override the guess, so a wrong classification costs a tap, not
/// a wrong entry.
enum AiIntent {
  task('Task', Icons.check_circle_outline_rounded),
  expense('Expense', Icons.account_balance_wallet_outlined),
  note('Note', Icons.description_outlined),
  bookmark('Bookmark', Icons.bookmark_outline_rounded),
  toBuy('To Buy', Icons.shopping_bag_outlined),
  watchItem('Watch', Icons.play_circle_outline_rounded),
  vaultItem('Vault', Icons.lock_outline_rounded),
  project('Project', Icons.folder_outlined),
  search('Search', Icons.search_rounded),
  question('Ask', Icons.help_outline_rounded);

  const AiIntent(this.label, this.icon);

  /// The chip label in the AI sheet's mode row.
  final String label;

  final IconData icon;

  /// [isCreate] is true for the intents that write something. Search and
  /// Ask only read, so the sheet keeps its results on screen rather than closing.
  bool get isCreate => switch (this) {
        AiIntent.task ||
        AiIntent.expense ||
        AiIntent.note ||
        AiIntent.bookmark ||
        AiIntent.toBuy ||
        AiIntent.watchItem ||
        AiIntent.vaultItem ||
        AiIntent.project =>
          true,
        AiIntent.search || AiIntent.question => false,
      };
}

/// [kAiConfidenceThreshold] is the score a parsed intent must reach before the
/// assistant acts on it without asking (Requirement 16.7).
///
/// Below it the sheet asks a clarifying question rather than creating something
/// half-understood — a task with no name, an expense with no amount — because a
/// wrong entry the user has to find and undo is worse than one more question.
///
/// It is the **default**, not the rule: the user can move it in Settings
/// (Requirement 25.3), and the live value reaches the parse through
/// `isConfidentAt`. This constant is what a fresh install starts at and what the
/// pure `isConfident` getters assume, so a test or a call site with no setting to
/// hand still gets the shipped behaviour.
const double kAiConfidenceThreshold = 0.6;

/// The bounds the Settings slider moves [kAiConfidenceThreshold] between.
///
/// Neither end is 0 or 1, on purpose. At 0 the assistant would act on anything,
/// including a line it pulled no title out of, and would silently create junk
/// entries; at 1 no parse could ever clear the bar and the assistant would ask a
/// clarifying question about input it had understood perfectly. Both ends are a
/// broken assistant the user could reach with one drag and would have no reason
/// to connect back to this slider.
const double kMinAiConfidence = 0.3;
const double kMaxAiConfidence = 0.9;
