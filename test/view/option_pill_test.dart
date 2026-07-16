import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Both the task sheet and the transaction sheet open with the caret already in a
/// field, and both set their options from a row of pills underneath it. Choosing
/// one used to close the keyboard: [PopupMenuButton] shows its menu by pushing a
/// route, and the new route takes the focus scope with it.
///
/// The field keeping **primary focus** is the whole of the fix — the keyboard is
/// up for exactly as long as that holds. These tests are what stop a later change
/// back to a route-based menu from quietly reintroducing it.
void main() {
  Future<FocusNode> pumpSheet(
    WidgetTester tester, {
    required ValueChanged<String> onSelected,
  }) async {
    final focus = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focus, autofocus: true),
              OptionPillMenu<String>(
                icon: Icons.folder_outlined,
                label: 'Category',
                isSet: false,
                accent: const Color(0xFFFFB300),
                onSelected: onSelected,
                entries: const [
                  PillOption(value: 'food', label: 'Food'),
                  PillDivider(),
                  PillOption(value: 'rent', label: 'Rent'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(focus.hasPrimaryFocus, isTrue, reason: 'the field starts focused');

    return focus;
  }

  testWidgets('the field keeps focus while the menu is open', (tester) async {
    final focus = await pumpSheet(tester, onSelected: (_) {});

    await tester.tap(find.byType(OptionPill));
    await tester.pumpAndSettle();

    expect(find.text('Food'), findsOneWidget, reason: 'the menu opened');
    expect(focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('the field keeps focus through a selection', (tester) async {
    final selected = <String>[];
    final focus = await pumpSheet(tester, onSelected: selected.add);

    await tester.tap(find.byType(OptionPill));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();

    expect(selected, ['rent']);
    expect(focus.hasPrimaryFocus, isTrue);
  });
}
