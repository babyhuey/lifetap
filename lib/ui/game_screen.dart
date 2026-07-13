import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/commander_art.dart';
import '../game/game_events.dart';
import '../game/game_state.dart';
import '../game/game_notifier.dart';
import '../touch/pointer_router.dart';
import 'life_delta.dart';
import 'seat_layout.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Height reserved for the toolbar strip so player zones never sit under it
/// (and toolbar touches never route into a zone). For 2/4/6 players the strip
/// splits the screen between the top and bottom rows; for 3/5 it sits at the
/// bottom.
const double _toolbarHeight = 64.0;

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final PointerRouter _router;
  final Map<int, Duration> _downAt = {};
  final Random _rng = Random();
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _router = PointerRouter(onResult: _onResult);
    // Drives hold auto-repeat: while a finger is held stationary in a zone the
    // router emits accelerating repeats on each tick. A no-op when nothing is
    // held, so the fixed interval costs almost nothing at rest.
    _holdTimer = Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _router.tick(),
    );
    _enableWakelock();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // No-op on platforms without the plugin (tests, some desktops).
    }
  }

  void _onResult(PointerResult result) {
    final session = ref.read(gameProvider);
    if (result.zoneId >= session.current.players.length) return;
    final playerId = session.current.players[result.zoneId].id;
    final delta = switch (result) {
      TapResult(:final magnitude) => magnitude,
      SwipeResult(:final magnitude) => magnitude,
    };
    ref
        .read(gameProvider.notifier)
        .dispatch(
          AdjustCounter(
            playerId: playerId,
            mode: CounterMode.life,
            delta: delta,
          ),
        );
    // Feed the transient floating "+N / −N" indicator for this seat; it sums
    // consecutive tap/hold changes and fades on its own.
    ref.read(lifeDeltaProvider.notifier).bump(playerId, delta);
  }

  void _onPointerDown(PointerDownEvent e) {
    _downAt[e.pointer] = e.timeStamp;
    _router.down(e.pointer, e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    _router.move(e.pointer, e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    final downAt = _downAt.remove(e.pointer) ?? e.timeStamp;
    _router.up(e.pointer, heldFor: e.timeStamp - downAt);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _downAt.remove(e.pointer);
    _router.cancel(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(gameProvider);
    final game = session.current;
    final players = game.players;

    return Scaffold(
      backgroundColor: LifeTapColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final layout = _layout(players.length, size);
          final rects = layout.zones;
          final turns = seatQuarterTurns(players.length);
          _router.zones = rects;
          _router.zoneTurns = turns;

          return Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: Stack(
                    children: [
                      for (var i = 0; i < players.length; i++)
                        Positioned.fromRect(
                          rect: rects[i],
                          child: _PlayerZone(
                            player: players[i],
                            quarterTurns: turns[i],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Gear affordances sit above the Listener at the zone's fixed
              // screen top-right corner (screen-framed, NOT seat-rotated) so they
              // share the grid's north-up frame and can't collide with the fixed
              // commander grid at the bottom-right. A tap opens the settings
              // dialog instead of the router reading it as a life tap. Only the
              // icon is hittable; the rest of each cell falls through.
              for (var i = 0; i < players.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      tooltip: 'Player settings',
                      color: Colors.white70,
                      iconSize: 20,
                      icon: const Icon(Icons.settings),
                      onPressed: () =>
                          _showPlayerSettings(players[i].id, turns[i]),
                    ),
                  ),
                ),
              // The counters affordance sits above the Listener at the zone's
              // fixed screen top-left corner (screen-framed, NOT seat-rotated) so
              // it shares the grid's north-up frame and can't collide with the
              // fixed commander grid at the bottom-right. Tapping it opens the
              // counters popup instead of routing a life tap; only its hit area
              // is consumed.
              for (var i = 0; i < players.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      key: ValueKey('counters-${players[i].id}'),
                      tooltip: 'Counters',
                      color: Colors.white70,
                      iconSize: 20,
                      icon: const Icon(Icons.grid_view),
                      onPressed: () => _showCounters(players[i].id, turns[i]),
                    ),
                  ),
                ),
              // The commander-damage cells sit above the Listener as a fixed
              // north-up mini-map of the table: the same seating order for every
              // seat (index 0 = top-left cell, etc.), NOT rotated to the player,
              // so the map reads the same from any seat. Only each cell's
              // number/label rotates to face its owner (see the grid below).
              // Anchored to the bottom-right of each zone. Only each cell's hit
              // area is consumed; the transparent rest of the Align falls
              // through to the Listener below (same pattern as the
              // gear/counters/name overlays).
              for (var i = 0; i < players.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: RotatedBox(
                    quarterTurns: 0,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _commanderDamageGrid(players, i, turns),
                      ),
                    ),
                  ),
                ),
              // Name labels render last so they stay on top of (and tappable
              // over) any commander-damage square that shares the seat's inner
              // edge; tapping a name opens the rename editor.
              for (var i = 0; i < players.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: RotatedBox(
                    quarterTurns: turns[i],
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _PlayerNameLabel(
                        name: players[i].name,
                        color: Color(players[i].color),
                        onTap: () => _editName(players[i].id, turns[i]),
                      ),
                    ),
                  ),
                ),
              // Monarch / Initiative badges float over the holder's zone near
              // the name pill, seat-rotated to face them. Wrapped in an
              // IgnorePointer so they never intercept a life tap; only shown for
              // whoever currently holds each status.
              for (var i = 0; i < players.length; i++)
                if (game.monarchId == players[i].id ||
                    game.initiativeId == players[i].id)
                  Positioned.fromRect(
                    rect: rects[i],
                    child: IgnorePointer(
                      child: RotatedBox(
                        quarterTurns: turns[i],
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: _ZoneStatusBadges(
                              monarch: game.monarchId == players[i].id,
                              initiative: game.initiativeId == players[i].id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              Positioned.fromRect(
                rect: layout.toolbar,
                child: _Toolbar(
                  playerCount: players.length,
                  dayNight: game.dayNight,
                  onDayNight: () =>
                      ref.read(gameProvider.notifier).cycleDayNight(),
                  onSettings: _openSettings,
                  onUndo: () => ref.read(gameProvider.notifier).undo(),
                  onDice: _showDice,
                  onCoin: _showCoin,
                  onHistory: _showHistory,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const SettingsScreen()),
    );
  }

  Future<void> _showDice() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _DicePopup(rng: _rng),
    );
  }

  Future<void> _showCoin() async {
    final heads = _rng.nextBool();
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _RollDialog(title: 'Coin flip', value: heads ? 'Heads' : 'Tails'),
    );
  }

  Future<void> _showHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: LifeTapColors.surface,
      builder: (context) => const _HistorySheet(),
    );
  }

  Future<void> _showPlayerSettings(int playerId, int quarterTurns) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _PlayerSettingsSheet(playerId: playerId, quarterTurns: quarterTurns),
    );
  }

  /// Applies a commander-damage change to [playerId] from [fromPlayerId]'s
  /// commander, reading the current "Commander damage life loss" setting so the
  /// life side tracks the toggle.
  void _adjustCommanderDamage(int playerId, int fromPlayerId, int delta) {
    final reduceLife = ref.read(settingsProvider).commanderDamageLifeLoss;
    ref
        .read(gameProvider.notifier)
        .dispatch(
          AdjustCommanderDamage(
            playerId: playerId,
            fromPlayerId: fromPlayerId,
            delta: delta,
            reduceLife: reduceLife,
          ),
        );
  }

  /// The fixed north-up commander-damage minimap for the player at [index]: one
  /// cell per player in seat/index order (index 0 = top-left cell, etc.), so the
  /// map reads the same from every seat. The current player's cell is the "me"
  /// tile, which shows their own art/color and opens their settings; every other
  /// cell shows that opponent's art/color plus this player's commander damage
  /// from them (tap +1 / long-press −1, clamped ≥ 0, 21+ flags red).
  ///
  /// The cells flow in a [Wrap] (2 columns) so a wide table can spill to a
  /// second row rather than overflow. The caller anchors this map at the zone's
  /// bottom-right WITHOUT seat rotation, so it reads north-up from every seat;
  /// each cell passes `quarterTurns: turns[index]` so only its number/label
  /// rotates to face this player.
  Widget _commanderDamageGrid(
    List<PlayerState> players,
    int index,
    List<int> turns,
  ) {
    final me = players[index];
    // One cell per player in seat/index order → a 2-column grid that mirrors
    // the on-screen seating (index 0 = top-left cell, etc.). The current
    // player's cell is the "me" tile.
    return SizedBox(
      width: 2 * _cmdrCellSize + _cmdrCellGap,
      child: Wrap(
        spacing: _cmdrCellGap,
        runSpacing: _cmdrCellGap,
        children: [
          for (var j = 0; j < players.length; j++)
            if (j == index)
              _CommanderDamageSquare(
                key: ValueKey('cmdr-me-${me.id}'),
                size: _cmdrCellSize,
                quarterTurns: turns[index],
                color: Color(me.color),
                artUrl: me.artUrl,
                label: 'me',
                onTap: () => _showPlayerSettings(me.id, turns[index]),
                onDecrement: null,
              )
            else
              _CommanderDamageSquare(
                key: ValueKey('cmdr-${me.id}-${players[j].id}'),
                size: _cmdrCellSize,
                quarterTurns: turns[index],
                color: Color(players[j].color),
                artUrl: players[j].artUrl,
                value: me.commanderDamage[players[j].id] ?? 0,
                onTap: () => _adjustCommanderDamage(me.id, players[j].id, 1),
                onDecrement: (me.commanderDamage[players[j].id] ?? 0) > 0
                    ? () => _adjustCommanderDamage(me.id, players[j].id, -1)
                    : null,
              ),
        ],
      ),
    );
  }

  /// Opens the seat-rotated counters popup: the fuller management view for this
  /// player's poison/energy/experience and generic named counters.
  Future<void> _showCounters(int playerId, int quarterTurns) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _CountersPopup(playerId: playerId, quarterTurns: quarterTurns),
    );
  }

  /// Opens the rename editor rotated to the player's seat facing
  /// ([quarterTurns], the same as that seat's zone content), so the field and
  /// live preview read right-side-up for that player — matching how their life
  /// number faces them. The system keyboard stays upright (an OS constraint);
  /// the editor is pinned to the top and lifted above the keyboard inset so the
  /// rotated field stays visible for every seat rotation.
  Future<void> _editName(int playerId, int quarterTurns) async {
    final current = ref.read(gameProvider).current.player(playerId).name;
    final inAppKeyboard = ref.read(settingsProvider).inAppKeyboard;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameEditDialog(
        initialName: current,
        quarterTurns: quarterTurns,
        inAppKeyboard: inAppKeyboard,
      ),
    );
    if (name == null) return; // cancelled or dismissed by an outside tap
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    ref
        .read(gameProvider.notifier)
        .dispatch(RenamePlayer(playerId: playerId, name: trimmed));
  }
}

/// Whether this player count splits into a top row and a bottom row with the
/// toolbar strip between them (2/4/6). 3 and 5 have no clean middle split, so
/// they keep the toolbar anchored at the bottom.
bool _splitLayout(int count) => count == 2 || count == 4 || count == 6;

/// The zone rectangles plus the toolbar rectangle for [count] players in a
/// screen of [size]. For 2/4/6 the toolbar is a middle strip: the top row sits
/// above it and the bottom row below, each row holding half the players. For
/// 3/5 the toolbar is a bottom strip and the zones fill the area above it via
/// [_zoneRects]. Either way the zones never overlap the strip, so a toolbar
/// touch is outside every zone and cannot register as a life tap.
({List<Rect> zones, Rect toolbar}) _layout(int count, Size size) {
  if (_splitLayout(count)) {
    final perRow = count ~/ 2;
    final rowHeight = (size.height - _toolbarHeight) / 2;
    final cellWidth = size.width / perRow;
    final zones = <Rect>[];
    for (var i = 0; i < count; i++) {
      final row = i ~/ perRow; // 0 = top row, 1 = bottom row
      final col = i % perRow;
      final top = row == 0 ? 0.0 : rowHeight + _toolbarHeight;
      zones.add(Rect.fromLTWH(col * cellWidth, top, cellWidth, rowHeight));
    }
    return (
      zones: zones,
      toolbar: Rect.fromLTWH(0, rowHeight, size.width, _toolbarHeight),
    );
  }
  final zoneArea = Size(size.width, size.height - _toolbarHeight);
  return (
    zones: _zoneRects(count, zoneArea),
    toolbar: Rect.fromLTWH(0, zoneArea.height, size.width, _toolbarHeight),
  );
}

/// Column-major grid: 1 column for 2 players, otherwise 2 columns. The last row
/// stretches its cells to fill the width when it holds fewer than a full row.
List<Rect> _zoneRects(int count, Size size) {
  final cols = count <= 2 ? 1 : 2;
  final rows = (count / cols).ceil();
  final rowHeight = size.height / rows;
  final rects = <Rect>[];
  for (var i = 0; i < count; i++) {
    final row = i ~/ cols;
    final inThisRow = (row == rows - 1) ? count - row * cols : cols;
    final colInRow = i - row * cols;
    final cellWidth = size.width / inThisRow;
    rects.add(
      Rect.fromLTWH(
        colInRow * cellWidth,
        row * rowHeight,
        cellWidth,
        rowHeight,
      ),
    );
  }
  return rects;
}

/// Side length and inter-cell gap of a commander-damage grid cell.
const double _cmdrCellSize = 40;
const double _cmdrCellGap = 4;

/// True when Auto-KO is on AND the player is dead (see [PlayerState.isDead]) —
/// used only for the knocked-out visual, never for game logic. Lethal commander
/// damage KOs regardless of the "life loss" toggle, matching [PlayerState.isDead].
bool _knockedOut(PlayerState player, GameSettings settings) {
  return settings.autoKo && player.isDead;
}

/// Luminance-weighted saturation matrix that maps every color to its grey
/// value; used to desaturate a knocked-out zone's art.
const List<double> _greyscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

class _PlayerZone extends ConsumerWidget {
  const _PlayerZone({required this.player, required this.quarterTurns});

  final PlayerState player;
  final int quarterTurns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ko = _knockedOut(player, settings);
    final delta = ref.watch(lifeDeltaProvider)[player.id] ?? 0;
    final base = Color(player.color);
    final solid = Color.lerp(base, Colors.black, 0.6)!;
    final art = player.artUrl;

    Widget? artLayer;
    if (art != null) {
      // Falls back to the solid color while loading or on any error, so a
      // missing/broken image never leaves the zone blank.
      artLayer = Image.network(
        art,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => ColoredBox(color: solid),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : ColoredBox(color: solid),
      );
      // Knocked out: drain the art's color so the zone reads as out.
      if (ko) {
        artLayer = ColorFiltered(
          colorFilter: const ColorFilter.matrix(_greyscaleMatrix),
          child: artLayer,
        );
      }
    }

    return DecoratedBox(
      // Without art the zone reads near-black and uses the player's color only
      // as a border accent; with art it keeps the neutral divider hairline so
      // the image itself carries the color.
      decoration: BoxDecoration(
        color: art != null ? LifeTapColors.background : LifeTapColors.emptyZone,
        border: Border.fromBorderSide(
          art != null
              ? const BorderSide(color: LifeTapColors.divider, width: 1)
              : BorderSide(color: base, width: 3),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (artLayer != null) ...[
            artLayer,
            // Scrim so the white life number and name stay legible over art.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
          ],
          // Knocked out: a dark overlay dims the whole zone (over the art/color
          // background, under the seat-rotated KO mark) so a dead seat reads out.
          if (ko) const ColoredBox(color: Color(0x8C000000)),
          // The ± hints and the life number share one rotated frame so they
          // read from the player's seat: "−" lands on the player's actual left
          // and "+" on their right, matching the router's per-seat tap sign.
          RotatedBox(
            quarterTurns: quarterTurns,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EdgeHint(alignment: Alignment.centerLeft, icon: Icons.remove),
                _EdgeHint(alignment: Alignment.centerRight, icon: Icons.add),
                _ZoneContent(player: player, knockedOut: ko),
                Align(
                  alignment: const Alignment(0, -0.45),
                  child: _LifeDeltaLabel(delta: delta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A low-opacity ± glyph pinned to one side edge of the player's (rotated)
/// frame. Purely decorative: it adds no hit target, so taps fall through to the
/// life router.
class _EdgeHint extends StatelessWidget {
  const _EdgeHint({required this.alignment, required this.icon});

  final Alignment alignment;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(icon, size: 34, color: Colors.white.withValues(alpha: 0.3)),
      ),
    );
  }
}

/// The floating "+N / −N" indicator that briefly appears near a player's life
/// number when their life changes from the tap/hold path. It shows the summed
/// change over the accumulation window (green gains, red losses) and fades out
/// once the window clears [delta] back to 0. Display-only: it carries no hit
/// target, so taps fall through to the life router. Sits inside the seat's
/// [RotatedBox] so it reads from the player's seat.
class _LifeDeltaLabel extends StatefulWidget {
  const _LifeDeltaLabel({required this.delta});

  final int delta;

  @override
  State<_LifeDeltaLabel> createState() => _LifeDeltaLabelState();
}

class _LifeDeltaLabelState extends State<_LifeDeltaLabel> {
  // The last non-zero value, retained so the label still reads its number while
  // it fades out after the window resets the delta to 0; back to 0 once faded.
  int _shown = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.delta;
    _visible = widget.delta != 0;
  }

  @override
  void didUpdateWidget(_LifeDeltaLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.delta != 0) {
      _shown = widget.delta;
      _visible = true;
    } else {
      _visible = false; // start fading out, keeping _shown for the label text
    }
  }

  @override
  Widget build(BuildContext context) {
    // Idle and fully faded: render nothing at all.
    if (!_visible && _shown == 0) return const SizedBox.shrink();
    final positive = _shown >= 0;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 350),
        onEnd: () {
          if (!_visible && _shown != 0) setState(() => _shown = 0);
        },
        child: Text(
          '${positive ? '+' : '−'}${_shown.abs()}',
          style: TextStyle(
            color: positive ? LifeTapColors.positive : LifeTapColors.negative,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The seat-rotated content of a zone: the huge life number plus the outer-edge
/// counter chip cluster. Rotated as a unit so it reads from the player's seat.
class _ZoneContent extends StatelessWidget {
  const _ZoneContent({required this.player, required this.knockedOut});

  final PlayerState player;
  final bool knockedOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = constraints.biggest.shortestSide * 0.42;
        return Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  // Knocked out: the big life number is replaced by the skull +
                  // "KO" mark, which shares this seat-rotated frame so it faces
                  // the player like the number did.
                  child: knockedOut
                      ? const _KnockedOutMark()
                      : Text(
                          '${player.life}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w800,
                            shadows: const [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                // Lifted off the player-facing bottom edge so the chips clear
                // it and the commander-damage squares floating over the zone.
                padding: const EdgeInsets.only(bottom: 46),
                child: knockedOut
                    ? Opacity(
                        opacity: 0.5,
                        child: _CounterChips(player: player),
                      )
                    : _CounterChips(player: player),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The knocked-out mark shown in place of a dead player's life number: a large
/// skull glyph over the word "KO". Rendered inside the zone's seat-rotated frame
/// so it faces the player, and inside a [FittedBox] so it scales to the zone.
class _KnockedOutMark extends StatelessWidget {
  const _KnockedOutMark();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '💀',
          style: TextStyle(
            fontSize: 120,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
        ),
        Text(
          'KO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact wrap of small rounded chips for the player's non-zero secondary
/// counters (poison, energy, experience, and generic named counters). Commander
/// damage has its own per-opponent strip. Shows nothing when all are zero.
class _CounterChips extends StatelessWidget {
  const _CounterChips({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (player.poison > 0)
        _CounterChip(
          icon: Icons.water_drop,
          value: player.poison,
          color: LifeTapColors.poison,
        ),
      if (player.energy > 0)
        _CounterChip(
          icon: Icons.bolt,
          value: player.energy,
          color: LifeTapColors.accent,
        ),
      if (player.experience > 0)
        _CounterChip(
          icon: Icons.auto_awesome,
          value: player.experience,
          color: LifeTapColors.accent,
        ),
      for (final type in _genericCounterTypes)
        if ((player.counters[type.label] ?? 0) > 0)
          _CounterChip(
            icon: type.icon,
            value: player.counters[type.label]!,
            color: LifeTapColors.accent,
          ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _CounterChip extends StatelessWidget {
  const _CounterChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LifeTapColors.chip,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One commander-damage grid cell ([size] on a side, radius 8). It sizes
/// itself so it can flow inside the per-player [Wrap] grid; the grid as a whole
/// is seat-rotated by the game screen, so each cell passes `quarterTurns: 0`.
/// Its fill is the pictured player's commander art via [Image.network]
/// ([BoxFit.cover]) when [artUrl] is set, falling back to their solid [color]
/// while loading, on error, or when no art exists — so the color never
/// disappears. The fill/number/label are wrapped in a [RotatedBox]([quarterTurns])
/// (a no-op at 0, kept for the general case). A legibility scrim sits over the
/// fill so the overlaid number (opponent cell) or [label] ("me" cell) stays
/// readable. Opaque so its tap is consumed by this overlay rather than falling
/// through to the life router below. An opponent cell at 21+ ([value] lethal)
/// flags red (border + wash); the "me" cell passes a null [value] and carries
/// no damage number.
class _CommanderDamageSquare extends StatelessWidget {
  const _CommanderDamageSquare({
    super.key,
    required this.size,
    required this.quarterTurns,
    required this.color,
    required this.artUrl,
    required this.onTap,
    required this.onDecrement,
    this.value,
    this.label,
  });

  final double size;
  final int quarterTurns;
  final Color color;
  final String? artUrl;
  final int? value;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final lethal = (value ?? 0) >= 21;
    final art = artUrl;
    // Art when available, the pictured player's color otherwise — the fallback
    // also covers the loading and error states so a cell is never blank.
    final Widget fill = art != null
        ? Image.network(
            art,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => ColoredBox(color: color),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : ColoredBox(color: color),
          )
        : ColoredBox(color: color);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onDecrement,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: LifeTapColors.chip,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: lethal ? LifeTapColors.negative : LifeTapColors.divider,
            width: lethal ? 2 : 1,
          ),
        ),
        // The square's position is physical; only its content rotates so the
        // art/number/"me" label read right-side-up for the player.
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: Stack(
            fit: StackFit.expand,
            children: [
              fill,
              // Scrim so the white number/label stays legible over art or a
              // bright fallback color.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              // Lethal (21+): a red wash reinforcing the red border.
              if (lethal)
                ColoredBox(
                  color: LifeTapColors.negative.withValues(alpha: 0.35),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value == null ? (label ?? '') : '$value',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: value == null ? 12 : 16,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tappable player-name pill pinned to the top edge of a zone. It carries
/// [HitTestBehavior.opaque] so its own hit area consumes taps (opening the
/// rename editor) while the surrounding cell falls through to the life router.
class _PlayerNameLabel extends StatelessWidget {
  const _PlayerNameLabel({
    required this.name,
    required this.color,
    required this.onTap,
  });

  final String name;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          decoration: BoxDecoration(
            // Player's color at ~30% over a translucent-black base: a per-seat
            // tint that stays legible over both near-black zones and art.
            color: Color.alphaBlend(
              color.withValues(alpha: 0.30),
              Colors.black.withValues(alpha: 0.6),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Display-only status badges (crown for Monarch, medal for Initiative) shown
/// over the holder's zone near the name pill. Rendered inside the seat's
/// [RotatedBox] so they face the player and inside an [IgnorePointer] so they
/// never consume a life tap. Only the badges for statuses this player holds are
/// built.
class _ZoneStatusBadges extends StatelessWidget {
  const _ZoneStatusBadges({required this.monarch, required this.initiative});

  final bool monarch;
  final bool initiative;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (monarch) const _ZoneStatusBadge(emoji: '👑'),
        if (monarch && initiative) const SizedBox(width: 6),
        if (initiative) const _ZoneStatusBadge(icon: Icons.military_tech),
      ],
    );
  }
}

/// One round status badge: a Unicode [emoji] glyph or a Material [icon] on a
/// translucent-black disc so it reads over both art and near-black zones.
class _ZoneStatusBadge extends StatelessWidget {
  const _ZoneStatusBadge({this.emoji, this.icon});

  final String? emoji;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        shape: BoxShape.circle,
        border: Border.all(color: LifeTapColors.accent, width: 1.5),
      ),
      child: emoji != null
          ? Text(emoji!, style: const TextStyle(fontSize: 16))
          : Icon(icon, size: 16, color: LifeTapColors.accent),
    );
  }
}

/// A rotated modal sheet (readable from the player's seat) to rename the
/// player, set their commander (resolving art on submit), and recolor.
class _PlayerSettingsSheet extends ConsumerStatefulWidget {
  const _PlayerSettingsSheet({
    required this.playerId,
    required this.quarterTurns,
  });

  final int playerId;
  final int quarterTurns;

  @override
  ConsumerState<_PlayerSettingsSheet> createState() =>
      _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends ConsumerState<_PlayerSettingsSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _commanderController;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    final player = ref.read(gameProvider).current.player(widget.playerId);
    _nameController = TextEditingController(text: player.name);
    _commanderController = TextEditingController(
      text: player.commanderName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commanderController.dispose();
    super.dispose();
  }

  void _submitName(String value) {
    final name = value.trim();
    if (name.isEmpty) return;
    ref
        .read(gameProvider.notifier)
        .dispatch(RenamePlayer(playerId: widget.playerId, name: name));
  }

  Future<void> _submitCommander(String value) async {
    final name = value.trim();
    final notifier = ref.read(gameProvider.notifier);
    if (name.isEmpty) {
      notifier.dispatch(
        SetCommander(
          playerId: widget.playerId,
          commanderName: null,
          artUrl: null,
        ),
      );
      return;
    }
    setState(() => _resolving = true);
    final art = await ref.read(commanderArtSourceProvider).artUrl(name);
    if (!mounted) return;
    setState(() => _resolving = false);
    final existingArt = ref
        .read(gameProvider)
        .current
        .player(widget.playerId)
        .artUrl;
    notifier.dispatch(
      SetCommander(
        playerId: widget.playerId,
        commanderName: name,
        // Keep existing art when the lookup fails rather than blanking the zone.
        artUrl: art ?? existingArt,
      ),
    );
    if (art == null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t find art for "$name"')));
    }
  }

  void _recolor(int color) {
    ref
        .read(gameProvider.notifier)
        .dispatch(RecolorPlayer(playerId: widget.playerId, color: color));
  }

  /// In-app-keyboard path for a field: pop the shared seat-rotated [_NameEditDialog]
  /// (captioned [label]) seeded with [controller]'s text; on a non-null result
  /// write it back and run [onSubmit] (the same handler the native field uses on
  /// submit — commander keeps its async Scryfall art resolution).
  Future<void> _editField(
    TextEditingController controller,
    String label,
    void Function(String) onSubmit,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NameEditDialog(
        initialName: controller.text,
        quarterTurns: widget.quarterTurns,
        inAppKeyboard: true,
        label: label,
      ),
    );
    if (result == null) return;
    controller.text = result;
    onSubmit(result);
    // onSubmit may refuse or normalize the value (an empty/whitespace name isn't
    // applied), so re-seed the edited read-only field from the authoritative
    // game state rather than the raw input — otherwise a rejected rename would
    // leave the field showing the blank string. Re-sync only the field that was
    // edited so the two stay independent. The name submit is synchronous, so its
    // field can always re-sync; the commander submit resolves art asynchronously,
    // so its field must keep the just-typed name until the dispatch lands (skip
    // the re-sync while a lookup is still resolving).
    if (!mounted) return;
    final player = ref.read(gameProvider).current.player(widget.playerId);
    if (identical(controller, _nameController)) {
      setState(() => _nameController.text = player.name);
    } else if (identical(controller, _commanderController) && !_resolving) {
      setState(() => _commanderController.text = player.commanderName ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same toggle as the rename editor: on = tap a read-only field to open the
    // big seat-rotated in-app keyboard (no OS keyboard); off = native TextField.
    final inAppKeyboard = ref.watch(settingsProvider).inAppKeyboard;
    final Widget? suffix = _resolving
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : null;
    // A centered, width-constrained rotated card (same shape as the counters
    // popup) so a side-seat (q1/q3) rotation stays a compact panel instead of a
    // tight modal width flipping to a full-screen stretched height. The bottom
    // padding lifts it above the OS keyboard so the native-field path (in-app
    // keyboard OFF) never leaves the Commander field/swatches occluded; a no-op
    // when the in-app keyboard is on (the inset stays 0).
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: widget.quarterTurns,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                decoration: BoxDecoration(
                  color: _PopupColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (inAppKeyboard)
                      TextField(
                        key: const ValueKey('field-name'),
                        controller: _nameController,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'Name'),
                        onTap: () =>
                            _editField(_nameController, 'Name', _submitName),
                      )
                    else
                      TextField(
                        key: const ValueKey('field-name'),
                        controller: _nameController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(labelText: 'Name'),
                        onSubmitted: _submitName,
                      ),
                    const SizedBox(height: 12),
                    if (inAppKeyboard)
                      TextField(
                        key: const ValueKey('field-commander'),
                        controller: _commanderController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Commander',
                          suffixIcon: suffix,
                        ),
                        onTap: () => _editField(
                          _commanderController,
                          'Commander',
                          _submitCommander,
                        ),
                      )
                    else
                      TextField(
                        key: const ValueKey('field-commander'),
                        controller: _commanderController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Commander',
                          suffixIcon: suffix,
                        ),
                        onSubmitted: _submitCommander,
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final swatch in defaultColors)
                          GestureDetector(
                            onTap: () => _recolor(swatch),
                            child: CircleAvatar(
                              backgroundColor: Color(swatch),
                              radius: 16,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Seat-rotated rename editor. The live name preview, the field, and the
/// Cancel/Done buttons are wrapped in a [RotatedBox] of the player's seat
/// [quarterTurns] so the whole editing surface faces that seat — the same way
/// their life number does.
///
/// Two input modes, chosen by [inAppKeyboard]:
///  * `false` — the native path: an autofocused [TextField] with the OS
///    keyboard. The keyboard itself stays upright (an OS constraint we don't
///    fight); the panel is pinned to the top and lifted above the keyboard
///    inset, and a [FittedBox] scales the (possibly sideways) panel down to
///    whatever room is left.
///  * `true` (default) — a small [_InAppKeyboard] rendered inside the same
///    [RotatedBox], so the keys face the seat too. There is no editable field
///    (an on-screen field would summon the OS keyboard), just a bordered
///    display box with a caret. With no OS keyboard the panel is centered.
///
/// Prefilled with the current name; Done/submit (or the keyboard's return key)
/// pops the new name, an outside tap or Cancel pops null and leaves it unchanged.
class _NameEditDialog extends StatefulWidget {
  const _NameEditDialog({
    required this.initialName,
    required this.quarterTurns,
    required this.inAppKeyboard,
    this.label = 'Name',
  });

  final String initialName;
  final int quarterTurns;
  final bool inAppKeyboard;

  /// Field caption — the native field's `labelText` and the in-app panel's
  /// caption — so the same dialog reads 'Name' or 'Commander' as reused.
  final String label;

  @override
  State<_NameEditDialog> createState() => _NameEditDialogState();
}

class _NameEditDialogState extends State<_NameEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  // Shift starts on so the first typed letter is capitalized; each letter key
  // auto-unshifts. Only used by the in-app keyboard path.
  bool _shifted = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  // In-app keyboard edits: names are short, so we only ever append/remove at the
  // end — no mid-string cursor. The controller is the store, so both the preview
  // and the display box (ValueListenableBuilders) update for free.
  void _onKey(String ch) {
    _controller.text = _controller.text + (_shifted ? ch.toUpperCase() : ch);
    if (_shifted) setState(() => _shifted = false);
  }

  void _onBackspace() {
    final text = _controller.text;
    if (text.isNotEmpty) {
      _controller.text = text.substring(0, text.length - 1);
    }
  }

  void _onSpace() => _controller.text = '${_controller.text} ';

  void _onShift() => setState(() => _shifted = !_shifted);

  @override
  Widget build(BuildContext context) {
    if (widget.inAppKeyboard) {
      // No OS keyboard rises in this mode, so there is no inset to dodge: center
      // the rotated panel (preview + field + keys) so it faces the seat, and let
      // the FittedBox shrink it to fit tall side-seat (q1/q3) rotations.
      // Fill the screen with the rotated keyboard. A FittedBox only scales its
      // child UP when it is given tight constraints; SizedBox.expand supplies
      // them (an Align/loose parent would leave the panel at its natural size,
      // which is why it looked small before). contain then scales the rotated
      // panel to fill as much of the screen as its aspect ratio allows.
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: RotatedBox(
              quarterTurns: widget.quarterTurns,
              child: SizedBox(width: 320, child: _inAppPanel()),
            ),
          ),
        ),
      );
    }
    // The OS keyboard rises from the bottom; drop its height from the usable area
    // and keep the panel at the top so the rotated field is never occluded. The
    // FittedBox then scales the panel down to fit whatever height is left, which
    // matters most for the side seats (q1/q3) whose rotated panel is tallest.
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth - 32,
                  maxHeight: constraints.maxHeight - 32,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RotatedBox(
                    quarterTurns: widget.quarterTurns,
                    child: SizedBox(width: 300, child: _panel()),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The in-app-keyboard panel: live preview, a non-editable display box with a
  /// caret (so no OS keyboard is summoned), the on-screen keys, and Cancel/Done.
  Widget _inAppPanel() {
    return Material(
      color: LifeTapColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LifeTapColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final preview = value.text.trim();
                return Text(
                  preview.isEmpty ? 'Player name' : preview,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LifeTapColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            // Bordered display box styled like an input, showing the text with a
            // trailing caret. Not editable, so tapping it never opens the OS
            // keyboard — the on-screen keys below are the only way to type.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: LifeTapColors.chip,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LifeTapColors.divider),
                  ),
                  child: Text(
                    '${value.text}|',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LifeTapColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _InAppKeyboard(
              shifted: _shifted,
              onKey: _onKey,
              onBackspace: _onBackspace,
              onSpace: _onSpace,
              onShift: _onShift,
              onDone: _submit,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel() {
    return Material(
      color: LifeTapColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live preview of the typed name, facing the seat like the field.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final preview = value.text.trim();
                return Text(
                  preview.isEmpty ? 'Player name' : preview,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LifeTapColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: widget.label),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact on-screen QWERTY sized to match the ~320px rename panel, styled
/// with the app's dark tokens. It owns no text of its own — each key just fires
/// a callback so the parent dialog keeps the text. Letters render uppercase
/// while [shifted]. Deliberately minimal: no long-press, no numbers row, no
/// cursor movement (names are short). Placed inside the panel's [RotatedBox] so
/// the keys face the seat, which the OS keyboard can't do.
class _InAppKeyboard extends StatelessWidget {
  const _InAppKeyboard({
    required this.shifted,
    required this.onKey,
    required this.onBackspace,
    required this.onSpace,
    required this.onShift,
    required this.onDone,
  });

  final bool shifted;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;
  final VoidCallback onShift;
  final VoidCallback onDone;

  static const List<String> _row1 = [
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', //
  ];
  static const List<String> _row2 = [
    'a',
    's',
    'd',
    'f',
    'g',
    'h',
    'j',
    'k',
    'l',
  ];
  static const List<String> _row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _letterRow(_row1),
        const SizedBox(height: 6),
        _letterRow(_row2),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _KeyCap(
                onTap: onShift,
                highlighted: shifted,
                child: const Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: LifeTapColors.textPrimary,
                ),
              ),
            ),
            for (final ch in _row3) ...[
              const SizedBox(width: 6),
              Expanded(child: _letterKey(ch)),
            ],
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: _KeyCap(
                key: const ValueKey('key-backspace'),
                onTap: onBackspace,
                child: const Icon(
                  Icons.backspace_outlined,
                  size: 18,
                  color: LifeTapColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: _KeyCap(
                key: const ValueKey('key-space'),
                onTap: onSpace,
                child: const Text(
                  'space',
                  style: TextStyle(
                    color: LifeTapColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: _KeyCap(
                key: const ValueKey('key-done'),
                onTap: onDone,
                highlighted: true,
                child: const Icon(
                  Icons.check,
                  size: 18,
                  color: LifeTapColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _letterRow(List<String> letters) {
    return Row(
      children: [
        for (var i = 0; i < letters.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _letterKey(letters[i])),
        ],
      ],
    );
  }

  Widget _letterKey(String ch) {
    return _KeyCap(
      key: ValueKey('key-$ch'),
      onTap: () => onKey(ch),
      child: Text(
        shifted ? ch.toUpperCase() : ch,
        style: const TextStyle(
          color: LifeTapColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One key of the [_InAppKeyboard]: a rounded chip with a divider border that
/// runs its [onTap] when pressed. [highlighted] (shift-on, the return key) uses
/// the lighter unselected-chip fill so it reads as active.
class _KeyCap extends StatelessWidget {
  const _KeyCap({
    super.key,
    required this.child,
    required this.onTap,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted
              ? LifeTapColors.chipUnselected
              : LifeTapColors.chip,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LifeTapColors.divider),
        ),
        child: child,
      ),
    );
  }
}

/// Small centered result dialog shared by the d20 and coin-flip buttons.
class _RollDialog extends StatelessWidget {
  const _RollDialog({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LifeTapColors.surface,
      title: Text(title),
      content: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// The set of dice offered in the dice popup: the standard polyhedral set, each
/// with the shape drawn on its tile and the number of sides it rolls.
enum _DiceShape {
  triangle,
  squarePips,
  diamond,
  kite,
  pentagon,
  hexagon,
  circle,
}

class _DieDef {
  const _DieDef({
    required this.label,
    required this.sides,
    required this.shape,
  });
  final String label;
  final int sides;
  final _DiceShape shape;
}

const List<_DieDef> _diceDefs = [
  _DieDef(label: 'd4', sides: 4, shape: _DiceShape.triangle),
  _DieDef(label: 'd6', sides: 6, shape: _DiceShape.squarePips),
  _DieDef(label: 'd8', sides: 8, shape: _DiceShape.diamond),
  _DieDef(label: 'd10', sides: 10, shape: _DiceShape.kite),
  _DieDef(label: 'd12', sides: 12, shape: _DiceShape.pentagon),
  _DieDef(label: 'd20', sides: 20, shape: _DiceShape.hexagon),
];

/// The dice-and-coins popup: a dark rounded modal with a tile per standard die
/// (d4–d20, each drawn as its own painted shape) plus a coin. Tapping a die
/// rolls a uniform 1..N from the shared [rng] and shows the result; tapping the
/// coin shows Heads/Tails. All shapes are painted by [_DiceShapePainter] — no
/// external assets.
class _DicePopup extends StatefulWidget {
  const _DicePopup({required this.rng});

  final Random rng;

  @override
  State<_DicePopup> createState() => _DicePopupState();
}

class _DicePopupState extends State<_DicePopup> {
  String? _resultLabel;
  String? _resultValue;

  void _roll(_DieDef die) {
    setState(() {
      _resultLabel = die.label;
      _resultValue = '${widget.rng.nextInt(die.sides) + 1}';
    });
  }

  void _flipCoin() {
    setState(() {
      _resultLabel = 'Coin';
      _resultValue = widget.rng.nextBool() ? 'Heads' : 'Tails';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LifeTapColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'Dice & Coins',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    color: LifeTapColors.textSecondary,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final die in _diceDefs)
                        _DiceTile(
                          key: ValueKey('die-${die.label}'),
                          label: die.label,
                          shape: die.shape,
                          onTap: () => _roll(die),
                        ),
                      _DiceTile(
                        key: const ValueKey('die-coin'),
                        label: 'Coin',
                        shape: _DiceShape.circle,
                        onTap: _flipCoin,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _result(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _result() {
    if (_resultValue == null) {
      return const Text(
        'Tap a die or coin to roll',
        style: TextStyle(color: LifeTapColors.textSecondary, fontSize: 13),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _resultLabel!,
          style: const TextStyle(
            color: LifeTapColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _resultValue!,
          key: const ValueKey('dice-result'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// One dice/coin tile: its painted [shape] over the die [label], tappable to
/// roll. Opaque so the whole tile is one hit target.
class _DiceTile extends StatelessWidget {
  const _DiceTile({
    super.key,
    required this.label,
    required this.shape,
    required this.onTap,
  });

  final String label;
  final _DiceShape shape;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: LifeTapColors.chip,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LifeTapColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CustomPaint(painter: _DiceShapePainter(shape)),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws each die's distinguishing outline (triangle=d4, pipped square=d6,
/// diamond=d8, kite=d10, pentagon=d12, hexagon=d20, circle=coin) centered in
/// the paint box, in the accent color with a faint fill — our own shapes, no
/// image assets.
class _DiceShapePainter extends CustomPainter {
  const _DiceShapePainter(this.shape);

  final _DiceShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = LifeTapColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = LifeTapColors.accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2 - 1;

    void draw(Path path) {
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }

    switch (shape) {
      case _DiceShape.circle:
        canvas.drawCircle(c, r, fill);
        canvas.drawCircle(c, r, stroke);
      case _DiceShape.triangle:
        draw(_polygon(c, r, 3));
      case _DiceShape.pentagon:
        draw(_polygon(c, r, 5));
      case _DiceShape.hexagon:
        draw(_polygon(c, r, 6));
      case _DiceShape.diamond:
        draw(
          Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r, c.dy)
            ..lineTo(c.dx, c.dy + r)
            ..lineTo(c.dx - r, c.dy)
            ..close(),
        );
      case _DiceShape.kite:
        draw(
          Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r * 0.85, c.dy - r * 0.1)
            ..lineTo(c.dx, c.dy + r)
            ..lineTo(c.dx - r * 0.85, c.dy - r * 0.1)
            ..close(),
        );
      case _DiceShape.squarePips:
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: r * 1.7, height: r * 1.7),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, fill);
        canvas.drawRRect(rect, stroke);
        final pip = Paint()..color = LifeTapColors.accent;
        final d = r * 0.5;
        for (final o in [
          Offset(-d, -d),
          Offset(d, -d),
          Offset.zero,
          Offset(-d, d),
          Offset(d, d),
        ]) {
          canvas.drawCircle(c + o, r * 0.12, pip);
        }
    }
  }

  /// A regular [sides]-gon of radius [r] about [c], first vertex pointing up.
  Path _polygon(Offset c, double r, int sides) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final a = -pi / 2 + i * 2 * pi / sides;
      final p = Offset(c.dx + r * cos(a), c.dy + r * sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_DiceShapePainter oldDelegate) =>
      oldDelegate.shape != shape;
}

/// The slim toolbar strip: white icon buttons plus a cyan-ringed badge showing
/// the current player count. Reset and the badge both open the settings screen.
/// Sits between the rows for 2/4/6 players and at the bottom for 3/5.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.playerCount,
    required this.dayNight,
    required this.onDayNight,
    required this.onSettings,
    required this.onUndo,
    required this.onDice,
    required this.onCoin,
    required this.onHistory,
  });

  final int playerCount;
  final DayNight dayNight;
  final VoidCallback onDayNight;
  final VoidCallback onSettings;
  final VoidCallback onUndo;
  final VoidCallback onDice;
  final VoidCallback onCoin;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LifeTapColors.background,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'New game',
            color: Colors.white,
            onPressed: onSettings,
            icon: const Icon(Icons.refresh),
          ),
          _PlayerCountBadge(count: playerCount, onTap: onSettings),
          IconButton(
            tooltip: 'Undo',
            color: Colors.white,
            onPressed: onUndo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Dice',
            color: Colors.white,
            onPressed: onDice,
            icon: const Icon(Icons.casino),
          ),
          IconButton(
            tooltip: 'Coin flip',
            color: Colors.white,
            onPressed: onCoin,
            icon: const Icon(Icons.monetization_on),
          ),
          IconButton(
            tooltip: 'Day/Night',
            onPressed: onDayNight,
            icon: switch (dayNight) {
              DayNight.none => Icon(
                Icons.brightness_medium,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              DayNight.day => const Icon(
                Icons.wb_sunny,
                color: Color(0xFFFDD835),
              ),
              DayNight.night => const Icon(
                Icons.nightlight_round,
                color: LifeTapColors.accent,
              ),
            },
          ),
          IconButton(
            tooltip: 'History',
            color: Colors.white,
            onPressed: onHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
    );
  }
}

class _PlayerCountBadge extends StatelessWidget {
  const _PlayerCountBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Players',
      onPressed: onTap,
      icon: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: LifeTapColors.accent, width: 2),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Color-coded, newest-first history read from the event log. Each life or
/// counter change shows the player's color dot, name, a counter icon, a signed
/// delta chip, and the resulting value. Watches the game so undo updates live.
class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(gameProvider);
    final entries = <_HistoryEntry>[];
    var state = const GameState(players: [], startingLife: 20);
    for (final event in session.history) {
      final before = state;
      state = event.apply(state);
      entries.add(_HistoryEntry.from(event, before, state));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Text(
                  'History',
                  style: TextStyle(
                    color: LifeTapColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => ref.read(gameProvider.notifier).undo(),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Undo'),
                  style: TextButton.styleFrom(
                    foregroundColor: LifeTapColors.accent,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: LifeTapColors.divider, height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = entries.length - 1; i >= 0; i--)
                  _HistoryTile(entry: entries[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How a history entry's delta chip is colored: by life sign, or accent for
/// any non-life counter change.
enum _DeltaKind { positive, negative, counter, none }

/// A flattened, display-ready projection of one [GameEvent] for the history
/// list, computed from the state just before and after the event ran.
class _HistoryEntry {
  const _HistoryEntry({
    this.color,
    this.icon,
    this.delta,
    this.result,
    this.kind = _DeltaKind.none,
    required this.text,
  });

  final Color? color;
  final IconData? icon;
  final int? delta;
  final int? result;
  final _DeltaKind kind;
  final String text;

  factory _HistoryEntry.from(
    GameEvent event,
    GameState before,
    GameState after,
  ) {
    if (event is AdjustCounter) {
      final p = after.player(event.playerId);
      final isLife = event.mode == CounterMode.life;
      return _HistoryEntry(
        color: Color(p.color),
        icon: _counterIcon(event.mode),
        delta: event.delta,
        result: p.counter(event.mode),
        kind: isLife
            ? (event.delta >= 0 ? _DeltaKind.positive : _DeltaKind.negative)
            : _DeltaKind.counter,
        text: p.name,
      );
    }
    if (event is AdjustCommanderDamage) {
      final p = after.player(event.playerId);
      return _HistoryEntry(
        color: Color(p.color),
        icon: Icons.shield,
        delta: event.delta,
        result: p.commanderDamage[event.fromPlayerId] ?? 0,
        kind: _DeltaKind.counter,
        text: p.name,
      );
    }
    if (event is AdjustNamedCounter) {
      final p = after.player(event.playerId);
      return _HistoryEntry(
        color: Color(p.color),
        icon: _namedCounterIcon(event.name),
        delta: event.delta,
        result: p.counters[event.name] ?? 0,
        kind: _DeltaKind.counter,
        text: p.name,
      );
    }
    // Rename/recolor/set-commander carry a player color dot; NewGame is neutral.
    final playerId = switch (event) {
      RenamePlayer(:final playerId) => playerId,
      RecolorPlayer(:final playerId) => playerId,
      SetCommander(:final playerId) => playerId,
      _ => null,
    };
    return _HistoryEntry(
      color: playerId == null ? null : Color(after.player(playerId).color),
      text: event.describe(before),
    );
  }

  static IconData _counterIcon(CounterMode mode) => switch (mode) {
    CounterMode.life => Icons.favorite,
    CounterMode.poison => Icons.water_drop,
    CounterMode.energy => Icons.bolt,
    CounterMode.experience => Icons.auto_awesome,
  };

  /// The icon for a generic named counter, matching the counters popup's tile
  /// icon for known types (Treasure/Storm/Rad) with a neutral fallback.
  static IconData _namedCounterIcon(String name) {
    for (final type in _genericCounterTypes) {
      if (type.label == name) return type.icon;
    }
    return Icons.casino;
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final deltaColor = switch (entry.kind) {
      _DeltaKind.positive => LifeTapColors.positive,
      _DeltaKind.negative => LifeTapColors.negative,
      _DeltaKind.counter => LifeTapColors.accent,
      _DeltaKind.none => LifeTapColors.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.color ?? LifeTapColors.divider,
            ),
          ),
          const SizedBox(width: 10),
          if (entry.icon != null) ...[
            Icon(entry.icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              entry.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.delta != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: deltaColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${entry.delta! >= 0 ? '+' : ''}${entry.delta}',
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '→ ${entry.result}',
              style: const TextStyle(
                color: LifeTapColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A counter type offered in the counters popup. A non-null [mode] means one of
/// the fixed poison/energy/experience counters; a null [mode] means a generic
/// named counter stored in [PlayerState.counters] keyed by [label].
class _CounterTypeDef {
  const _CounterTypeDef({required this.label, required this.icon, this.mode});

  final String label;
  final IconData icon;
  final CounterMode? mode;
}

const List<_CounterTypeDef> _standardCounterTypes = [
  _CounterTypeDef(
    label: 'Poison',
    icon: Icons.water_drop,
    mode: CounterMode.poison,
  ),
  _CounterTypeDef(label: 'Energy', icon: Icons.bolt, mode: CounterMode.energy),
  _CounterTypeDef(
    label: 'Experience',
    icon: Icons.auto_awesome,
    mode: CounterMode.experience,
  ),
];

/// Generic increment counters. The special single-holder/global counters
/// (Monarch, Initiative, Day/night) and KO-as-counter are deliberately out of
/// this pass — they need extra ownership logic.
const List<_CounterTypeDef> _genericCounterTypes = [
  _CounterTypeDef(label: 'Treasure', icon: Icons.savings),
  _CounterTypeDef(label: 'Storm', icon: Icons.cyclone),
  _CounterTypeDef(label: 'Rad', icon: Icons.radar),
];

/// The bright-surface palette for the counters popup, which deliberately breaks
/// from the app's dark theme to match the reference's light modal.
abstract final class _PopupColors {
  static const surface = Color(0xFFEDEFF2);
  static const tile = Color(0xFFFFFFFF);
  static const tileBorder = Color(0xFFD5D9E0);
  static const textPrimary = Color(0xFF1B1F24);
  static const textSecondary = Color(0xFF5C6470);
}

enum _CounterTab { player, counters }

/// The seat-rotated counters popup: a light rounded modal with a Player/Counters
/// toggle, a grid of counter-type tiles to add counters, and the player's active
/// counters as larger tap-to-increment tiles. Tapping a tile adds +1 (creating a
/// generic counter on first touch); holding an active tile removes one (clamped
/// at 0). Every change dispatches through the notifier so undo/history stay
/// correct. Commander damage keeps its own per-zone grid and is not duplicated
/// here.
class _CountersPopup extends ConsumerStatefulWidget {
  const _CountersPopup({required this.playerId, required this.quarterTurns});

  final int playerId;
  final int quarterTurns;

  @override
  ConsumerState<_CountersPopup> createState() => _CountersPopupState();
}

class _CountersPopupState extends ConsumerState<_CountersPopup> {
  _CounterTab _tab = _CounterTab.counters;

  void _bump(_CounterTypeDef type, int delta) {
    final notifier = ref.read(gameProvider.notifier);
    final mode = type.mode;
    if (mode != null) {
      notifier.dispatch(
        AdjustCounter(playerId: widget.playerId, mode: mode, delta: delta),
      );
    } else {
      notifier.dispatch(
        AdjustNamedCounter(
          playerId: widget.playerId,
          name: type.label,
          delta: delta,
        ),
      );
    }
  }

  int _value(_CounterTypeDef type, PlayerState player) {
    final mode = type.mode;
    return mode != null
        ? player.counter(mode)
        : (player.counters[type.label] ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider).current;
    final player = game.player(widget.playerId);
    return Center(
      child: RotatedBox(
        quarterTurns: widget.quarterTurns,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340, maxHeight: 520),
            child: Container(
              decoration: BoxDecoration(
                color: _PopupColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: _tab == _CounterTab.counters
                          ? _countersBody(game, player)
                          : _playerBody(player),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tap to increment. Hold for additional options.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _PopupColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        // Scales down rather than overflowing when the seat rotation leaves the
        // modal narrow.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _segmentedToggle(),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          color: _PopupColors.textSecondary,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _segmentedToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _PopupColors.tile,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _PopupColors.tileBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segButton('Player', _CounterTab.player),
          _segButton('Counters', _CounterTab.counters),
        ],
      ),
    );
  }

  Widget _segButton(String label, _CounterTab tab) {
    final selected = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? LifeTapColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _PopupColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _countersBody(GameState game, PlayerState player) {
    final all = [..._standardCounterTypes, ..._genericCounterTypes];
    final active = [
      for (final t in all)
        if (_value(t, player) > 0) t,
    ];
    final inactive = [
      for (final t in all)
        if (_value(t, player) == 0) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusSection(game, player),
        if (active.isNotEmpty) ...[
          _sectionLabel('Active'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in active) _activeTile(t, _value(t, player)),
            ],
          ),
          const SizedBox(height: 18),
        ],
        _sectionLabel('Add counter'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in inactive) _paletteTile(t)],
        ),
      ],
    );
  }

  /// The single-holder / global status row: Monarch and Initiative toggle onto
  /// this player, Day/Night cycles the table-wide state. Each highlights when
  /// active (this player holds it, or day/night is set) and routes through the
  /// notifier so undo/history stay correct.
  Widget _statusSection(GameState game, PlayerState player) {
    final notifier = ref.read(gameProvider.notifier);
    final (
      IconData dnIcon,
      String dnLabel,
      bool dnActive,
    ) = switch (game.dayNight) {
      DayNight.none => (Icons.brightness_medium, 'Day/Night', false),
      DayNight.day => (Icons.wb_sunny, 'Day', true),
      DayNight.night => (Icons.nightlight_round, 'Night', true),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Status'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _statusTile(
              icon: Icons.workspace_premium,
              label: 'Monarch',
              active: game.monarchId == player.id,
              onTap: () => notifier.toggleMonarch(player.id),
            ),
            _statusTile(
              icon: Icons.military_tech,
              label: 'Initiative',
              active: game.initiativeId == player.id,
              onTap: () => notifier.toggleInitiative(player.id),
            ),
            _statusTile(
              icon: dnIcon,
              label: dnLabel,
              active: dnActive,
              onTap: notifier.cycleDayNight,
            ),
          ],
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: active ? LifeTapColors.accent : _PopupColors.tile,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? LifeTapColors.accent : _PopupColors.tileBorder,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? Colors.white : _PopupColors.textPrimary,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? Colors.white : _PopupColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _PopupColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _paletteTile(_CounterTypeDef type) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _bump(type, 1),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: _PopupColors.tile,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _PopupColors.tileBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, color: _PopupColors.textPrimary, size: 24),
            const SizedBox(height: 6),
            Text(
              type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _PopupColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeTile(_CounterTypeDef type, int value) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _bump(type, 1),
      onLongPress: () => _bump(type, -1),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: LifeTapColors.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerBody(PlayerState player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(player.color),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              player.name,
              style: const TextStyle(
                color: _PopupColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Life ${player.life}',
          style: const TextStyle(
            color: _PopupColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Use the gear icon on the zone to rename or recolor.',
          style: TextStyle(color: _PopupColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}
