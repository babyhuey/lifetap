import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('tapping a player name opens a seat-rotated editor and renames '
      'without changing life', (tester) async {
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

    // The editor is showing, prefilled with the current name; life is untouched
    // (still four seats at 40).
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('40'), findsNWidgets(4));

    // The editing surface is rotated to P1's seat: in the default four-player
    // game seat 0 (top-left) faces the left side, i.e. quarterTurns 1. The
    // TextField's nearest RotatedBox ancestor is the editor's own wrapper.
    final rotated = tester.widget<RotatedBox>(
      find
          .ancestor(
            of: find.byType(TextField),
            matching: find.byType(RotatedBox),
          )
          .first,
    );
    expect(rotated.quarterTurns, 1);

    // Enter a new name and confirm — works regardless of the RotatedBox.
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // RenamePlayer was applied: the label now reads the new name, the old one
    // is gone, and no life changed.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('P1'), findsNothing);
    expect(find.text('40'), findsNWidgets(4));
  });
}
