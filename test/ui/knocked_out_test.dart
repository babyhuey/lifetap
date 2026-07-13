import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('a player driven to 0 life shows the KO mark while the others '
      'still show their number', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Four players start at 40; nobody is knocked out yet.
    expect(find.text('40'), findsNWidgets(4));
    expect(find.text('KO'), findsNothing);

    // Drive player 0 to exactly 0 life (a lethal threshold with Auto-KO on).
    container
        .read(gameProvider.notifier)
        .dispatch(
          const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -40),
        );
    await tester.pump();

    expect(container.read(gameProvider).current.player(0).life, 0);

    // Exactly that player shows the skull + "KO" in place of the number; the
    // other three still show 40.
    expect(find.text('💀'), findsOneWidget);
    expect(find.text('KO'), findsOneWidget);
    expect(find.text('40'), findsNWidgets(3));
  });
}
