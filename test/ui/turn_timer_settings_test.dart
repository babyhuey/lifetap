import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('turnTimerEnabled defaults off, turnTimerSeconds defaults to 60', () {
    final settings = container.read(settingsProvider);
    expect(settings.turnTimerEnabled, isFalse);
    expect(settings.turnTimerSeconds, 60);
  });

  test('setTurnTimerEnabled and setTurnTimerSeconds update independently', () {
    container.read(settingsProvider.notifier).setTurnTimerEnabled(true);
    expect(container.read(settingsProvider).turnTimerEnabled, isTrue);
    expect(container.read(settingsProvider).turnTimerSeconds, 60);

    container.read(settingsProvider.notifier).setTurnTimerSeconds(90);
    expect(container.read(settingsProvider).turnTimerSeconds, 90);
    expect(container.read(settingsProvider).turnTimerEnabled, isTrue);
  });

  test('turnTimerSecondsOptions offers the four presets', () {
    expect(turnTimerSecondsOptions, [30, 60, 90, 120]);
  });
}
