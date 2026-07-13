import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifetap/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a tap on a player changes exactly one life by one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: LifeTapApp()));
    await tester.pump();

    // Four players start at 40.
    expect(find.text('40'), findsNWidgets(4));

    // Tap the centre of one player's life number. It is display-only, so the
    // tap falls through to the pointer router and changes that player's life by
    // one. The sign depends on the seat's rotation, so accept +1 or -1 — this
    // keeps the test robust to layout/rotation changes.
    await tester.tapAt(tester.getCenter(find.text('40').first));
    await tester.pump();

    expect(find.text('40'), findsNWidgets(3));
    final wentUp = find.text('41').evaluate().length;
    final wentDown = find.text('39').evaluate().length;
    expect(
      wentUp + wentDown,
      1,
      reason: 'exactly one player should change by one step',
    );
  });
}
