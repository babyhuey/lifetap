/// Quarter-turn rotation for each seat's content so it faces that player's
/// physical seat at the table. The returned list has one entry per player,
/// indexed by player position.
///
/// A quarterTurns value is: 0 = upright (faces the bottom edge), 2 = faces the
/// top edge, 1 and 3 = the two side edges.
List<int> seatQuarterTurns(int playerCount) {
  switch (playerCount) {
    case 2:
      return const [2, 0]; // stacked halves: top faces down, bottom faces up
    case 3:
      return const [1, 3, 0]; // left edge, right edge, bottom
    case 4:
      // 2x2 [TL, TR, BL, BR]: the left column reads from the left side (q1) and
      // the right column reads from the right side (q3), so each player faces a
      // side edge rather than the top/bottom.
      return const [1, 3, 1, 3];
    case 5:
      return const [2, 2, 0, 0, 3]; // 2 top, 2 bottom, 1 on the right side
    case 6:
      return const [2, 2, 2, 0, 0, 0]; // 3 top face down, 3 bottom face up
    default:
      return List.filled(playerCount, 0);
  }
}
