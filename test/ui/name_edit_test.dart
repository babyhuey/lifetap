import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  testWidgets('with the in-app keyboard ON (default), typing on the seat '
      'keyboard renames without summoning the OS keyboard', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    // Baseline: default four-player game, each seat at 40 life, P1 present.
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('40'), findsNWidgets(4));

    // Tapping the name label must open the editor, not adjust life.
    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();

    // In-app mode uses no editable field, so the OS keyboard is never summoned;
    // the on-screen keys are present instead.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('key-a')), findsOneWidget);

    // The editing surface is rotated to P1's seat: seat 0 (top-left) faces the
    // left side, i.e. quarterTurns 1.
    final rotated = tester.widget<RotatedBox>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('key-a')),
            matching: find.byType(RotatedBox),
          )
          .first,
    );
    expect(rotated.quarterTurns, 1);

    // Clear the prefilled 'P1' with backspace, then type "Ab".
    await tester.tap(find.byKey(const ValueKey('key-backspace')));
    await tester.tap(find.byKey(const ValueKey('key-backspace')));
    await tester.pump();
    // Shift starts on, so the first letter is capitalized, then auto-unshifts.
    await tester.tap(find.byKey(const ValueKey('key-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('key-b')));
    await tester.pump();

    // The live preview reflects the typed name and the display box shows it with
    // a trailing caret; life is untouched.
    expect(find.text('Ab'), findsOneWidget);
    expect(find.text('Ab|'), findsOneWidget);
    expect(find.text('40'), findsNWidgets(4));

    // The keyboard's return key commits the rename (same as Done).
    await tester.tap(find.byKey(const ValueKey('key-done')));
    await tester.pumpAndSettle();

    // RenamePlayer was applied: the label now reads the new name, the old one is
    // gone, and no life changed.
    expect(find.text('Ab'), findsOneWidget);
    expect(find.text('P1'), findsNothing);
    expect(find.text('40'), findsNWidgets(4));
  });

  testWidgets('with the in-app keyboard OFF, the native text field still '
      'renames without changing life', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setInAppKeyboard(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('P1'), findsOneWidget);
    expect(find.text('40'), findsNWidgets(4));

    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();

    // The native editable field is present (and life is untouched).
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('40'), findsNWidgets(4));

    // The editor is rotated to P1's seat (quarterTurns 1).
    final rotated = tester.widget<RotatedBox>(
      find
          .ancestor(
            of: find.byType(TextField),
            matching: find.byType(RotatedBox),
          )
          .first,
    );
    expect(rotated.quarterTurns, 1);

    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('P1'), findsNothing);
    expect(find.text('40'), findsNWidgets(4));
  });
}
