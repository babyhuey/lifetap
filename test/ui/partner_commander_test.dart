import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/commander_art.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

/// Resolves any name to a fixed URL immediately, keyed by the exact name, so
/// a test can tell which of the two fields' submissions actually resolved.
class _FakeArtSource implements CommanderArtSource {
  @override
  Future<String?> artUrl(String commanderName) =>
      Future.value('http://art/$commanderName');
}

void main() {
  testWidgets('submitting the partner field resolves art and dispatches '
      'SetPartnerCommander independently of the primary commander field', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        commanderArtSourceProvider.overrideWithValue(_FakeArtSource()),
      ],
    );
    addTearDown(container.dispose);
    // The native fields' onSubmitted wiring (used below via enterText +
    // TextInputAction.done) only exists in OFF mode — ON mode's read-only
    // fields are driven by tapping to open the seat keyboard instead.
    container.read(settingsProvider.notifier).setInAppKeyboard(false);
    container.read(gameProvider.notifier).newGame(2, 20);

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

    await tester.enterText(
      find.byKey(const ValueKey('field-commander')),
      'Atraxa',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('field-partner')),
      'Thrasios',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final player = container.read(gameProvider).current.player(id);
    expect(player.commanderName, 'Atraxa');
    expect(player.artUrl, 'http://art/Atraxa');
    expect(player.partnerCommanderName, 'Thrasios');
    expect(player.partnerArtUrl, 'http://art/Thrasios');
  });

  testWidgets(
    'setting only a partner, with the primary commander never touched, '
    'resolves correctly and leaves the primary fields null',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          commanderArtSourceProvider.overrideWithValue(_FakeArtSource()),
        ],
      );
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).setInAppKeyboard(false);
      container.read(gameProvider.notifier).newGame(2, 20);

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

      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Kraum',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final player = container.read(gameProvider).current.player(id);
      expect(player.partnerCommanderName, 'Kraum');
      expect(player.partnerArtUrl, 'http://art/Kraum');
      expect(player.commanderName, isNull);
      expect(player.artUrl, isNull);
    },
  );

  testWidgets(
    'submitting the partner field before the primary commander field still '
    'leaves both resolved independently, regardless of submission order',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          commanderArtSourceProvider.overrideWithValue(_FakeArtSource()),
        ],
      );
      addTearDown(container.dispose);
      // The native fields' onSubmitted wiring (used below via enterText +
      // TextInputAction.done) only exists in OFF mode — ON mode's read-only
      // fields are driven by tapping to open the seat keyboard instead.
      container.read(settingsProvider.notifier).setInAppKeyboard(false);
      container.read(gameProvider.notifier).newGame(2, 20);

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

      // Opposite order from the test above: partner submitted first, then
      // the primary commander — the two fields must not clobber each other
      // regardless of which is submitted first.
      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Thrasios',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('field-commander')),
        'Atraxa',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final player = container.read(gameProvider).current.player(id);
      expect(player.commanderName, 'Atraxa');
      expect(player.artUrl, 'http://art/Atraxa');
      expect(player.partnerCommanderName, 'Thrasios');
      expect(player.partnerArtUrl, 'http://art/Thrasios');
    },
  );

  testWidgets(
    'a failed partner lookup keeps the previously-resolved partner art and '
    'does not touch the primary commander',
    (tester) async {
      var partnerFails = false;
      final source = _ToggleFailArtSource(() => partnerFails);
      final container = ProviderContainer(
        overrides: [commanderArtSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      // The native fields' onSubmitted wiring (used below via enterText +
      // TextInputAction.done) only exists in OFF mode — ON mode's read-only
      // fields are driven by tapping to open the seat keyboard instead.
      container.read(settingsProvider.notifier).setInAppKeyboard(false);
      container.read(gameProvider.notifier).newGame(2, 20);

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

      await tester.enterText(
        find.byKey(const ValueKey('field-commander')),
        'Atraxa',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Thrasios',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        container.read(gameProvider).current.player(id).partnerArtUrl,
        'http://art/Thrasios',
      );

      partnerFails = true;
      await tester.enterText(
        find.byKey(const ValueKey('field-partner')),
        'Kraum',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final player = container.read(gameProvider).current.player(id);
      expect(player.partnerCommanderName, 'Kraum');
      expect(
        player.partnerArtUrl,
        'http://art/Thrasios',
        reason: 'a failed lookup must not blank the previously-resolved art',
      );
      expect(
        player.commanderName,
        'Atraxa',
        reason: 'the partner field must never touch the primary commander',
      );
      expect(player.artUrl, 'http://art/Atraxa');

      await tester.pumpAndSettle(const Duration(seconds: 5));
    },
  );
}

/// Resolves to a fixed URL unless [shouldFail] reads true at call time, in
/// which case it returns null — models a lookup that starts working and
/// later fails, independent per call rather than a one-shot toggle.
class _ToggleFailArtSource implements CommanderArtSource {
  _ToggleFailArtSource(this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<String?> artUrl(String commanderName) =>
      Future.value(shouldFail() ? null : 'http://art/$commanderName');
}
