import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

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

  testWidgets('lethal commander damage shows the KO mark even with '
      '"life loss" OFF (Auto-KO on)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Auto-KO stays on; the "commander damage life loss" rule is turned off, so
    // the 21 damage never touched life — the KO must still fire off the counter.
    container.read(settingsProvider.notifier).setCommanderDamageLifeLoss(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // 21 commander damage on player 0 from player 1, with life untouched
    // (reduceLife: false, mirroring the life-loss-off setting).
    container
        .read(gameProvider.notifier)
        .dispatch(
          const AdjustCommanderDamage(
            playerId: 0,
            fromPlayerId: 1,
            delta: 21,
            reduceLife: false,
          ),
        );
    await tester.pump();

    final player = container.read(gameProvider).current.player(0);
    expect(player.life, 40, reason: 'life untouched with life loss off');
    expect(player.isDead, isTrue, reason: '21 from one opponent is lethal');

    expect(find.text('KO'), findsOneWidget);
    expect(
      find.text('40'),
      findsNWidgets(3),
      reason: 'the KO seat shows no 40',
    );
  });

  testWidgets('with Auto-KO OFF a dead player shows their number, not the KO '
      'mark', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setAutoKo(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Drive player 0 to 0 life: dead, but Auto-KO is off so no mark is shown.
    container
        .read(gameProvider.notifier)
        .dispatch(
          const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -40),
        );
    await tester.pump();

    expect(container.read(gameProvider).current.player(0).isDead, isTrue);
    // No KO mark anywhere, so the dead seat falls back to its life number — the
    // other three seats still uniquely show their big "40".
    expect(find.text('KO'), findsNothing);
    expect(find.text('💀'), findsNothing);
    expect(
      find.text('40'),
      findsNWidgets(3),
      reason: 'the living seats render normally; the dead seat shows 0, not KO',
    );
  });
}
