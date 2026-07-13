import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifetap/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping to a player\'s right increases that player\'s life', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: LifeTapApp()));
    await tester.pump();

    expect(find.text('40'), findsNWidgets(4));

    // Player 0's top-left zone spans x 0..400 and is an upside-down top seat
    // (quarterTurns 2), so that player's right is the screen's LEFT. A quick
    // tap there increments their life by one.
    final gesture = await tester.startGesture(const Offset(120, 120));
    await gesture.up();
    await tester.pump();

    expect(find.text('41'), findsOneWidget);
    expect(find.text('40'), findsNWidgets(3));
  });
}
