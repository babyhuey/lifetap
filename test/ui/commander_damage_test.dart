import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  testWidgets('tapping an opponent chip adds commander damage and, with the '
      'life-loss setting on, drops life by one', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Life-loss is on by default; player 0 has taken no commander damage yet.
    expect(container.read(settingsProvider).commanderDamageLifeLoss, isTrue);
    final before = container.read(gameProvider).current.player(0);
    expect(before.commanderDamage[1] ?? 0, 0);
    expect(before.life, 40);

    // Player 0's chip for opponent 1.
    await tester.tap(find.byKey(const ValueKey('cmdr-0-1')));
    await tester.pump();

    final after = container.read(gameProvider).current.player(0);
    expect(after.commanderDamage[1], 1);
    expect(after.life, 39, reason: 'life drops by 1 when life-loss is on');
  });

  testWidgets('with the life-loss setting off, the chip adds damage but leaves '
      'life unchanged', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    container.read(settingsProvider.notifier).setCommanderDamageLifeLoss(false);
    await tester.pump();

    final before = container.read(gameProvider).current.player(0);
    expect(before.life, 40);

    await tester.tap(find.byKey(const ValueKey('cmdr-0-2')));
    await tester.pump();

    final after = container.read(gameProvider).current.player(0);
    expect(after.commanderDamage[2], 1);
    expect(after.life, 40, reason: 'life is untouched when life-loss is off');
  });
}
