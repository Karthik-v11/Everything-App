import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [Category] labels a task (Work, Personal, Study, …).
///
/// Categories are rows rather than an enum: Requirement 4 lists "Custom" among
/// them, so the user can add their own.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    this.iconName,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final int colorValue;
  final String? iconName;
  final bool isDefault;

  Color get color => Color(colorValue);

  factory Category.fromEntry(CategoryEntry entry) => Category(
        id: entry.id,
        name: entry.name,
        colorValue: entry.colorValue,
        iconName: entry.iconName,
        isDefault: entry.isDefault,
      );

  CategoriesTableCompanion toCompanion() => CategoriesTableCompanion.insert(
        id: id,
        name: name,
        colorValue: colorValue,
        iconName: Value(iconName),
        isDefault: Value(isDefault),
      );

  Category copyWith({
    String? id,
    String? name,
    int? colorValue,
    String? iconName,
    bool? isDefault,
  }) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        iconName: iconName ?? this.iconName,
        isDefault: isDefault ?? this.isDefault,
      );

  @override
  List<Object?> get props => [id, name, colorValue, iconName, isDefault];
}

/// [kDefaultCategories] is the starter set seeded on first launch, from
/// `initial-requirements.md`. "Custom" is not among them: it names the user's own
/// categories rather than being one.
const List<({String name, int color, String icon})> kDefaultCategories = [
  (name: 'Work', color: 0xFF6366F1, icon: 'work'),
  (name: 'Personal', color: 0xFF2FA84F, icon: 'person'),
  (name: 'Study', color: 0xFF2C6BED, icon: 'school'),
  (name: 'Health', color: 0xFFE8453C, icon: 'favorite'),
  (name: 'Shopping', color: 0xFFF5622D, icon: 'shopping_cart'),
  (name: 'Finance', color: 0xFFFFB300, icon: 'payments'),
  (name: 'Travel', color: 0xFF4FC3C7, icon: 'flight'),
];
