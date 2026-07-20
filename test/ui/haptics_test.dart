import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/game_screen.dart';

void main() {
  /// Captures every HapticFeedback.* platform message sent during the test.
  List<MethodCall> captureHaptics(WidgetTester tester) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  testWidgets('a life tap fires a haptic tick', (tester) async {
    final haptics = captureHaptics(tester);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    // Same open spot as life_delta_test: top-left zone, clear of overlays.
    await tester.tapAt(const Offset(110, 210));
    await tester.pump();

    expect(find.text('41'), findsOneWidget, reason: 'the tap counted');
    expect(haptics, isNotEmpty);
  });

  testWidgets('a commander-damage cell tap fires a haptic tick', (
    tester,
  ) async {
    final haptics = captureHaptics(tester);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('cmdr-0-1')));
    await tester.pump();

    expect(haptics, isNotEmpty);
  });

  testWidgets('a toolbar button fires a haptic tick', (tester) async {
    final haptics = captureHaptics(tester);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GameScreen())),
    );
    await tester.pump();

    // Make a life change so Undo is enabled, then discard those haptics.
    await tester.tapAt(const Offset(110, 210));
    await tester.pump();
    haptics.clear();

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();

    expect(haptics, isNotEmpty);
  });
}
