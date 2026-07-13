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

  testWidgets('each zone has a "me" identity holder; tapping it opens the '
      "player's settings sheet and records no commander damage", (
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

    // A four-player game has one "me" holder per seat.
    expect(find.byKey(const ValueKey('cmdr-me-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('cmdr-me-3')), findsOneWidget);

    final before = container.read(gameProvider).current.player(0);

    // Tapping "me" opens the rename/commander settings sheet, not a counter.
    await tester.tap(find.byKey(const ValueKey('cmdr-me-0')));
    await tester.pumpAndSettle();
    expect(find.text('Commander'), findsOneWidget);

    // It is a pure identity holder: no life or commander-damage change.
    final after = container.read(gameProvider).current.player(0);
    expect(after.commanderDamage, before.commanderDamage);
    expect(after.life, before.life);
  });

  testWidgets('commander-damage cells form a compact grid: player 0 has a '
      '"me" cell plus one cell per opponent, and tapping an opponent cell '
      'records damage and life loss', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Default 4-player game: player 0's grid is a seating mini-map with one cell
    // per player in seat order — player 0's own "me" cell plus one cell per
    // opponent — all present as hit targets regardless of their grid position.
    expect(find.byKey(const ValueKey('cmdr-me-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('cmdr-0-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cmdr-0-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('cmdr-0-3')), findsOneWidget);

    // The opponent-1 cell is live: tapping it records damage and, with the
    // life-loss setting on, drops player 0's life by one.
    final before = container.read(gameProvider).current.player(0);
    expect(before.commanderDamage[1] ?? 0, 0);

    await tester.tap(find.byKey(const ValueKey('cmdr-0-1')));
    await tester.pump();

    final after = container.read(gameProvider).current.player(0);
    expect(after.commanderDamage[1], 1);
    expect(after.life, before.life - 1);
  });
}
