import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('GameScreen boots with four players at 40 life', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    // Four seats, all showing the default 40 life.
    expect(find.text('40'), findsNWidgets(4));
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('P4'), findsOneWidget);
  });
}
