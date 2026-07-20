import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  testWidgets('commander-damage cells render at the 56px touch-target size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('cmdr-0-1'))),
      const Size(56, 56),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('cmdr-me-0'))),
      const Size(56, 56),
    );
  });
}
