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

    // Baseline is the default 4-player, 40-life game.
    expect(container.read(gameProvider).current.playerCount, 4);
    expect(container.read(gameProvider).current.startingLife, 40);

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

    // Auto-KO is the last toggle row.
    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    expect(container.read(settingsProvider).autoKo, isFalse);
  });

  testWidgets('the In-app keyboard toggle flips the settings flag', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // On by default.
    expect(container.read(settingsProvider).inAppKeyboard, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    // Tapping the row's title toggles its SwitchListTile.
    await tester.tap(find.text('In-app keyboard'));
    await tester.pump();

    expect(container.read(settingsProvider).inAppKeyboard, isFalse);
  });

  testWidgets('the offline-download row reports "Nothing to download" when no '
      'commander is set', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    // The default game has players but no commander names, so there is nothing
    // to pre-fetch — this path touches neither the network nor the disk cache.
    final row = find.text('Download commander art for offline');
    await tester.scrollUntilVisible(row, 120);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Nothing to download'), findsOneWidget);
  });
}
