import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets(
    'an empty zone (no commander art) shows the seeded texture layer',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('zone-texture-0')), findsOneWidget);
    },
  );

  testWidgets('setting commander art removes the texture layer', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    container
        .read(gameProvider.notifier)
        .dispatch(
          const SetCommander(
            playerId: 0,
            commanderName: 'Atraxa',
            artUrl: 'http://art/atraxa',
          ),
        );
    await tester.pump();

    expect(find.byKey(const ValueKey('zone-texture-0')), findsNothing);
  });

  testWidgets('recoloring a player changes the wash gradient color', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    final washFinder = find.descendant(
      of: find.byKey(const ValueKey('zone-texture-0')),
      matching: find.byType(DecoratedBox),
    );
    final before =
        (tester.widget<DecoratedBox>(washFinder).decoration as BoxDecoration)
                .gradient
            as RadialGradient;

    container
        .read(gameProvider.notifier)
        .dispatch(const RecolorPlayer(playerId: 0, color: 0xFF112233));
    await tester.pump();

    final after =
        (tester.widget<DecoratedBox>(washFinder).decoration as BoxDecoration)
                .gradient
            as RadialGradient;

    expect(after.colors, isNot(equals(before.colors)));
  });
}
