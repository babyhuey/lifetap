import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  testWidgets('selecting player/life chips and Start dispatches NewGame with '
      'the chosen values', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Baseline is the default 4-player, 20-life game.
    expect(container.read(gameProvider).current.playerCount, 4);
    expect(container.read(gameProvider).current.startingLife, 20);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    // Pick 2 players and a 60 starting life, then start.
    await tester.tap(find.text('2'));
    await tester.tap(find.text('60'));
    await tester.pump();
    await tester.tap(find.text('Start game'));
    await tester.pump();

    final current = container.read(gameProvider).current;
    expect(current.playerCount, 2);
    expect(current.startingLife, 60);
    expect(current.players.map((p) => p.life), everyElement(60));
  });

  testWidgets('the Auto-KO toggle flips the settings flag', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(settingsProvider).autoKo, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    // Auto-KO is the second (last) toggle row.
    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    expect(container.read(settingsProvider).autoKo, isFalse);
  });
}
