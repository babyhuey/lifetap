import 'package:flutter_test/flutter_test.dart';
import 'package:lifetap/ui/seat_layout.dart';

void main() {
  group('seatQuarterTurns', () {
    test('returns the documented facing for each player count 2..6', () {
      expect(seatQuarterTurns(2), [2, 0]);
      expect(seatQuarterTurns(3), [1, 3, 0]);
      expect(seatQuarterTurns(4), [2, 2, 0, 0]);
      expect(seatQuarterTurns(5), [2, 2, 0, 0, 3]);
      expect(seatQuarterTurns(6), [2, 2, 2, 0, 0, 0]);
    });

    test('length equals the player count for 2..6', () {
      for (var n = 2; n <= 6; n++) {
        expect(seatQuarterTurns(n), hasLength(n));
      }
    });
  });
}
