import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('tapping a seat\'s + side twice shows an accumulated "+2" '
      'floating indicator on that player', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    // Default 800x600 window, four-player split layout: the top-left zone is
    // Rect(0,0,400,268) with a q1 (left-facing) seat, so its center is (200,134)
    // and a tap below center reads as this player's own right (+).
    expect(find.text('40'), findsNWidgets(4));

    await tester.tapAt(const Offset(200, 190));
    await tester.tapAt(const Offset(200, 190));
    await tester.pump(); // rebuild; well within the 1.8s accumulation window

    // Both single-finger taps summed into one growing indicator, and only that
    // seat's life changed — confirming it targets the right player.
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('40'), findsNWidgets(3));
  });
}
