import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/settings_screen.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('hapticFeedback defaults on, soundEffects defaults off', () {
    final settings = container.read(settingsProvider);
    expect(settings.hapticFeedback, isTrue);
    expect(settings.soundEffects, isFalse);
  });

  test('setHapticFeedback and setSoundEffects update state independently', () {
    container.read(settingsProvider.notifier).setHapticFeedback(false);
    expect(container.read(settingsProvider).hapticFeedback, isFalse);
    expect(container.read(settingsProvider).soundEffects, isFalse);

    container.read(settingsProvider.notifier).setSoundEffects(true);
    expect(container.read(settingsProvider).soundEffects, isTrue);
    expect(container.read(settingsProvider).hapticFeedback, isFalse);
  });
}
