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

/// Returns whatever [next] currently is, so a test can flip a later lookup to a
/// failure (null) after an earlier success — modelling offline/404/timeout.
class _TogglingArtSource implements CommanderArtSource {
  String? next = 'http://art/original';

  @override
  Future<String?> artUrl(String commanderName) => Future.value(next);
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

  testWidgets('a failed lookup keeps the previously-resolved art and only '
      'updates the name', (tester) async {
    final source = _TogglingArtSource();
    final container = ProviderContainer(
      overrides: [commanderArtSourceProvider.overrideWithValue(source)],
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

    final commander = find.byKey(const ValueKey('field-commander'));

    // First submit resolves to a real URL.
    await tester.enterText(commander, 'Aaa');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      container.read(gameProvider).current.player(id).artUrl,
      'http://art/original',
    );

    // The lookup now fails; the name changes but the good art must survive.
    source.next = null;
    await tester.enterText(commander, 'Bbb');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final player = container.read(gameProvider).current.player(id);
    expect(player.commanderName, 'Bbb', reason: 'the name still updates');
    expect(
      player.artUrl,
      'http://art/original',
      reason: 'a failed lookup must not blank the previously-resolved art',
    );

    // The failure surfaces a SnackBar; let its auto-dismiss timer fire so no
    // timer outlives the test.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('player settings open as a compact centered dialog on a side '
      'seat, not a full-screen stretched sheet', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // Default 4-player table: player 0 is a left-column, side-facing (q1) seat —
    // exactly the rotation that used to flip the bottom sheet to a full-screen
    // stretch. Open settings via the "me" tile (the same path used above).
    final id = container.read(gameProvider).current.players.first.id;
    await tester.tap(find.byKey(ValueKey('cmdr-me-$id')));
    await tester.pumpAndSettle();

    // The card is the RotatedBox wrapping the settings fields.
    final card = find.ancestor(
      of: find.byKey(const ValueKey('field-name')),
      matching: find.byType(RotatedBox),
    );
    expect(card, findsOneWidget);

    final cardSize = tester.getSize(card);
    final screenSize = tester.getSize(find.byType(GameScreen));
    // A compact panel leaves clear margins on every side; the old full-bleed
    // sheet filled the screen once the seat rotation flipped its width to height.
    expect(cardSize.width, lessThan(screenSize.width - 100));
    expect(cardSize.height, lessThan(screenSize.height - 100));
  });
}
