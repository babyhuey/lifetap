import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:lifetap/game/game_notifier.dart';
import 'package:lifetap/ui/game_screen.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  Future<ProviderContainer> pumpGame(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('the bar holds only undo, dice, and the more menu; the old '
      'buttons are gone', (tester) async {
    await pumpGame(tester);

    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Dice'), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar-menu')), findsOneWidget);

    expect(find.byTooltip('New game'), findsNothing);
    expect(find.byTooltip('Players'), findsNothing);
    expect(find.byTooltip('Coin flip'), findsNothing);
    expect(find.byTooltip('Day/Night'), findsNothing);
    expect(find.byTooltip('History'), findsNothing);
    expect(find.byTooltip('Pick starting player'), findsNothing);
    // Turn timer off (default): no end-turn button at all.
    expect(find.byKey(const ValueKey('end-turn-icon')), findsNothing);
  });

  testWidgets('end turn appears on the bar only while the turn timer is on', (
    tester,
  ) async {
    final container = await pumpGame(tester);

    container.read(settingsProvider.notifier).setTurnTimerEnabled(true);
    await tester.pump();
    expect(find.byKey(const ValueKey('end-turn-icon')), findsOneWidget);

    container.read(settingsProvider.notifier).setTurnTimerEnabled(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('end-turn-icon')), findsNothing);
  });

  testWidgets('the menu lists the four labeled entries and new game routes '
      'to the settings screen', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byKey(const ValueKey('toolbar-menu')));
    await tester.pumpAndSettle();

    expect(find.textContaining('New game'), findsOneWidget);
    expect(find.textContaining('4 players'), findsOneWidget);
    expect(find.text('Pick starting player'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Day / Night'), findsOneWidget);

    await tester.tap(find.textContaining('New game'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the day/night entry shows the current state and cycles it', (
    tester,
  ) async {
    final container = await pumpGame(tester);
    expect(container.read(gameProvider).current.dayNight, DayNight.none);

    await tester.tap(find.byKey(const ValueKey('toolbar-menu')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Off'), findsOneWidget);

    await tester.tap(find.textContaining('Day / Night'));
    await tester.pumpAndSettle();
    expect(container.read(gameProvider).current.dayNight, DayNight.day);

    await tester.tap(find.byKey(const ValueKey('toolbar-menu')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Day', findRichText: true), findsWidgets);
  });

  testWidgets('the pick-starting-player entry launches the ritual overlay', (
    tester,
  ) async {
    await pumpGame(tester);

    await tester.tap(find.byKey(const ValueKey('toolbar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ritual-icon')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ritual-overlay')), findsOneWidget);
  });

  testWidgets('bar buttons, name pill, and popup tabs meet the 44px minimum '
      'tap target', (tester) async {
    await pumpGame(tester);

    for (final f in [
      find.byTooltip('Undo'),
      find.byTooltip('Dice'),
      find.byKey(const ValueKey('toolbar-menu')),
    ]) {
      final size = tester.getSize(f);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }

    final pill = tester.getSize(
      find
          .ancestor(of: find.text('P1'), matching: find.byType(GestureDetector))
          .first,
    );
    expect(pill.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const ValueKey('counters-0')));
    await tester.pumpAndSettle();
    final tab = tester.getSize(
      find
          .ancestor(
            of: find.text('Player'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(tab.height, greaterThanOrEqualTo(44));
  });
}
