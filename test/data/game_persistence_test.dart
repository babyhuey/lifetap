import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/data/game_persistence.dart';
import 'package:lifetap/game/game_events.dart';
import 'package:lifetap/game/game_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SharedPreferencesGamePersistence', () {
    test('load returns null when nothing has been saved', () async {
      final persistence = SharedPreferencesGamePersistence();
      expect(await persistence.load(), isNull);
    });

    test('save then load round-trips a multi-event history', () async {
      final persistence = SharedPreferencesGamePersistence();
      final history = <GameEvent>[
        const NewGame(playerCount: 3, startingLife: 30),
        const AdjustCounter(playerId: 0, mode: CounterMode.life, delta: -5),
        const RenamePlayer(playerId: 1, name: 'Bob'),
      ];

      await persistence.save(history);
      final loaded = await persistence.load();

      expect(loaded, isNotNull);
      expect(loaded!.length, 3);
      expect(loaded[0], isA<NewGame>());
      expect((loaded[0] as NewGame).playerCount, 3);
      expect(loaded[1], isA<AdjustCounter>());
      expect((loaded[1] as AdjustCounter).delta, -5);
      expect(loaded[2], isA<RenamePlayer>());
      expect((loaded[2] as RenamePlayer).name, 'Bob');
    });

    test('a later save overwrites an earlier one', () async {
      final persistence = SharedPreferencesGamePersistence();
      await persistence.save(const [NewGame(playerCount: 2, startingLife: 20)]);
      await persistence.save(const [NewGame(playerCount: 4, startingLife: 40)]);

      final loaded = await persistence.load();
      expect((loaded!.single as NewGame).playerCount, 4);
    });

    test('load returns null (never throws) on malformed stored JSON', () async {
      SharedPreferences.setMockInitialValues({
        'lifetap:saved-session': 'not valid json {{{',
      });
      final persistence = SharedPreferencesGamePersistence();

      expect(await persistence.load(), isNull);
    });

    test('load returns null (never throws) on a recognizable-JSON but unknown '
        'event type', () async {
      SharedPreferences.setMockInitialValues({
        'lifetap:saved-session': '[{"type":"NotARealEvent"}]',
      });
      final persistence = SharedPreferencesGamePersistence();

      expect(await persistence.load(), isNull);
    });
  });
}
