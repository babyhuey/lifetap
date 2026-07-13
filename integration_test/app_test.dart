import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifetap/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tapping the right half of a zone increases that player\'s life',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: LifeTapApp()));
      await tester.pump();

      expect(find.text('20'), findsNWidgets(4));

      // A quick tap in the right half of player 0's top-left zone (which spans
      // x 0..400) increments that player's life by one.
      final gesture = await tester.startGesture(const Offset(280, 120));
      await gesture.up();
      await tester.pump();

      expect(find.text('21'), findsOneWidget);
      expect(find.text('20'), findsNWidgets(3));
    },
  );
}
