import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [AccountType] is where the money sits (Requirement 12.3).
enum AccountType {
  cash('Cash', Icons.payments_rounded),
  bank('Bank', Icons.account_balance_rounded),
  creditCard('Credit Card', Icons.credit_card_rounded),
  wallet('Wallet', Icons.account_balance_wallet_rounded),
  upi('UPI', Icons.qr_code_rounded),
  custom('Custom', Icons.savings_rounded);

  const AccountType(this.label, this.icon);

  final String label;
  final IconData icon;

  static AccountType fromName(String? name) => AccountType.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AccountType.custom,
      );
}

/// [Account] is one place money is held (Requirement 12.3).
///
/// [openingBalanceMinor] is the balance the account had when it was added. The
/// current balance is not stored — it is the opening balance plus every
/// transaction on the account (see [FinanceState.balanceOf]). A stored running
/// balance would need every write to update two rows, and one missed update would
/// leave a balance that no longer matches its transactions.
///
/// A deleted account would orphan its transactions, so a finished account is
/// [isArchived] instead: hidden from the pickers, still explaining its history.
class Account extends Equatable {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.openingBalanceMinor = 0,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final bool isArchived;

  factory Account.fromEntry(AccountEntry entry) => Account(
        id: entry.id,
        name: entry.name,
        type: AccountType.fromName(entry.type),
        openingBalanceMinor: entry.openingBalanceMinor,
        isArchived: entry.isArchived,
      );

  AccountsTableCompanion toCompanion() => AccountsTableCompanion.insert(
        id: id,
        name: name,
        type: type.name,
        openingBalanceMinor: Value(openingBalanceMinor),
        isArchived: Value(isArchived),
      );

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    int? openingBalanceMinor,
    bool? isArchived,
  }) =>
      Account(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
        isArchived: isArchived ?? this.isArchived,
      );

  @override
  List<Object?> get props => [id, name, type, openingBalanceMinor, isArchived];
}

/// [kDefaultAccounts] is seeded on first launch: a transaction cannot be saved
/// without an account, so shipping none would make the first "Add transaction" a
/// detour through a screen the user has not found yet.
const List<({String name, AccountType type})> kDefaultAccounts = [
  (name: 'Cash', type: AccountType.cash),
  (name: 'Bank', type: AccountType.bank),
];
