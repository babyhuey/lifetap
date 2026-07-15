import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('zone commander art rotates with the seat so it faces the '
      'player, not the bottom of the tablet', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Default 4-player 2x2: left column seats read q1, right column q3.
    container
        .read(gameProvider.notifier)
        .dispatch(
          const SetCommander(
            playerId: 0,
            commanderName: 'Left Seat',
            artUrl: 'http://art/left',
          ),
        );
    container
        .read(gameProvider.notifier)
        .dispatch(
          const SetCommander(
            playerId: 3,
            commanderName: 'Right Seat',
            artUrl: 'http://art/right',
          ),
        );
    await tester.pump();

    final leftFrame = find.byKey(const ValueKey('zone-art-0'));
    final rightFrame = find.byKey(const ValueKey('zone-art-3'));

    // Each zone's art layer lives inside a frame rotated to that seat.
    expect(tester.widget<RotatedBox>(leftFrame).quarterTurns, 1);
    expect(tester.widget<RotatedBox>(rightFrame).quarterTurns, 3);
    expect(
      find.descendant(of: leftFrame, matching: find.byType(CachedNetworkImage)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rightFrame,
        matching: find.byType(CachedNetworkImage),
      ),
      findsOneWidget,
    );
  });
}
