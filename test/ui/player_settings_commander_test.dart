import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/commander_art.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

/// Resolves any name to a fixed URL immediately so the commander submit never
/// touches the network.
class _FakeArtSource implements CommanderArtSource {
  @override
  Future<String?> artUrl(String commanderName) =>
      Future.value('http://art/$commanderName');
}

void main() {
  testWidgets('with the in-app keyboard ON, tapping the Commander field opens '
      'the seat keyboard and Done dispatches SetCommander', (tester) async {
    final container = ProviderContainer(
      overrides: [
        commanderArtSourceProvider.overrideWithValue(_FakeArtSource()),
      ],
    );
    addTearDown(container.dispose);
    // inAppKeyboard defaults on.

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Open player 0's settings sheet via their "me" commander tile (a reliable
    // opaque target that opens the same sheet as the gear icon).
    final id = container.read(gameProvider).current.players.first.id;
    await tester.tap(find.byKey(ValueKey('cmdr-me-$id')));
    await tester.pumpAndSettle();

    // In ON mode the Commander field is read-only (no OS keyboard); tapping it
    // opens the in-app keyboard dialog captioned 'Commander'.
    await tester.tap(find.byKey(const ValueKey('field-commander')));
    await tester.pumpAndSettle();

    expect(find.text('Commander'), findsWidgets);
    expect(find.byKey(const ValueKey('key-a')), findsOneWidget);

    // Commander starts empty, so type "Xy" (shift capitalizes the first letter)
    // and commit with the keyboard's return key.
    await tester.tap(find.byKey(const ValueKey('key-x')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('key-y')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('key-done')));
    await tester.pumpAndSettle();

    final player = container.read(gameProvider).current.player(id);
    expect(player.commanderName, 'Xy');
    expect(player.artUrl, 'http://art/Xy');
  });

  testWidgets('with the in-app keyboard OFF, the native Commander field still '
      'resolves and dispatches SetCommander', (tester) async {
    final container = ProviderContainer(
      overrides: [
        commanderArtSourceProvider.overrideWithValue(_FakeArtSource()),
      ],
    );
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setInAppKeyboard(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    final id = container.read(gameProvider).current.players.first.id;
    await tester.tap(find.byKey(ValueKey('cmdr-me-$id')));
    await tester.pumpAndSettle();

    // OFF mode keeps the native editable field.
    final commander = find.byKey(const ValueKey('field-commander'));
    expect(commander, findsOneWidget);
    await tester.enterText(commander, 'Zed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final player = container.read(gameProvider).current.player(id);
    expect(player.commanderName, 'Zed');
    expect(player.artUrl, 'http://art/Zed');
  });
}
