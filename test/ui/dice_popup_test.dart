import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('the dice popup shows every die plus a coin, and tapping one '
      'rolls a numeric result', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    // The toolbar dice button opens the new popup.
    await tester.tap(find.byTooltip('Dice'));
    await tester.pumpAndSettle();

    // The full polyhedral set plus a coin are present as tiles.
    expect(find.byKey(const ValueKey('die-d4')), findsOneWidget);
    expect(find.byKey(const ValueKey('die-d6')), findsOneWidget);
    expect(find.byKey(const ValueKey('die-d12')), findsOneWidget);
    expect(find.byKey(const ValueKey('die-d20')), findsOneWidget);
    expect(find.byKey(const ValueKey('die-coin')), findsOneWidget);

    // Nothing is shown until a die is rolled.
    expect(find.byKey(const ValueKey('dice-result')), findsNothing);

    // Rolling the d20 shows a numeric result in 1..20.
    await tester.tap(find.byKey(const ValueKey('die-d20')));
    await tester.pump();

    final result = tester.widget<Text>(
      find.byKey(const ValueKey('dice-result')),
    );
    expect(int.parse(result.data!), inInclusiveRange(1, 20));
  });
}
