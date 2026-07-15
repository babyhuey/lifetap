import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  testWidgets(
    'enabling the timer shows a full-duration badge on player 0; End Turn '
    'moves it to player 1 with a reset countdown',
    (tester) async {
      var now = Duration.zero;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).setTurnTimerEnabled(true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GameScreen(clock: () => now)),
        ),
      );
      await tester.pump();
      now = const Duration(milliseconds: 60);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('60'), findsOneWidget);

      // Tap without advancing `now` again: _endTurn() recomputes the
      // deadline from the *current* clock value, so checking immediately
      // (no further clock advancement) keeps the expected remaining time at
      // exactly the full duration — advancing `now` again here before the
      // check would make the assertion depend on exact elapsed-ms/1000
      // truncation instead of testing the actual reset behavior.
      await tester.tap(find.byKey(const ValueKey('end-turn-icon')));
      await tester.pump();

      expect(find.text('60'), findsOneWidget);
      // The badge is on player[1]'s zone, not player[0]'s.
      final badgeFinder = find.text('60');
      final badgeZoneRect = tester.getRect(badgeFinder);
      expect(badgeZoneRect.center.dx, greaterThan(400));
    },
  );

  testWidgets('the countdown badge is absent when the setting is off, and '
      'disappears if the setting is turned off mid-game', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('turn-timer-badge')), findsNothing);

    container.read(settingsProvider.notifier).setTurnTimerEnabled(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('turn-timer-badge')), findsOneWidget);

    container.read(settingsProvider.notifier).setTurnTimerEnabled(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('turn-timer-badge')), findsNothing);
  });

  testWidgets('a fresh new game resets turn tracking to player 0', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setTurnTimerEnabled(true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    await tester.tap(find.byKey(const ValueKey('end-turn-icon')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    container.read(gameProvider.notifier).newGame(4, 40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final badgeZoneRect = tester.getRect(
      find.byKey(const ValueKey('turn-timer-badge')),
    );
    expect(badgeZoneRect.center.dx, lessThan(400));
  });

  testWidgets(
    'the badge switches to the warning color once the deadline passes, '
    'without blocking normal life taps',
    (tester) async {
      var now = Duration.zero;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).setTurnTimerEnabled(true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GameScreen(clock: () => now)),
        ),
      );
      await tester.pump();
      // First tick: activates tracking with a deadline computed from
      // `now`=60ms (deadline = 60ms + 60s). Advancing `now` to 61s *before*
      // this pump (instead of after) would make the very first tick already
      // see the far-future value and compute the deadline from THAT, so the
      // remaining time would still read a full 60s afterward — `now` is a
      // static variable the injected clock reads, not real elapsed time, so
      // it never advances on its own between pumps.
      now = const Duration(milliseconds: 60);
      await tester.pump(const Duration(milliseconds: 60));

      // Now push `now` well past the deadline and let one more tick observe
      // it and repaint.
      now = const Duration(seconds: 61);
      await tester.pump(const Duration(milliseconds: 60));
      // Scoped to the badge itself: the default 4-player game's
      // commander-damage grid also renders a "0" per opponent cell
      // (unconditionally, regardless of the timer), so a bare
      // find.text('0') matches those too.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('turn-timer-badge')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );

      final id = container.read(gameProvider).current.players.first.id;
      final before = container.read(gameProvider).current.player(id).life;
      await tester.tapAt(const Offset(110, 210));
      expect(
        container.read(gameProvider).current.player(id).life,
        isNot(before),
        reason: 'the timer hitting zero must never block a life tap',
      );
      // Drains the life-tap's floating-indicator fade timer before the test
      // ends: it's owned by lifeDeltaProvider on the externally-created
      // `container`, which UncontrolledProviderScope doesn't dispose on
      // unmount, so it would otherwise still be pending when the test
      // framework checks for leaked timers.
      await tester.pump(const Duration(milliseconds: 1800));
    },
  );
}
