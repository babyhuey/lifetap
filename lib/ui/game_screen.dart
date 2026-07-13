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
      ScrubResult(:final steps) => steps,
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
    final players = session.current.players;

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
              // Gear affordances sit above the Listener so a tap opens the
              // settings sheet instead of the router reading it as a life tap.
              // Only the icon is hittable; the rest of each cell falls through.
              for (var i = 0; i < players.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: RotatedBox(
                    quarterTurns: turns[i],
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
                ),
              // Name labels also sit above the Listener so tapping a name opens
              // the rename editor instead of the router reading it as a life
              // tap. Only the label's hit area is consumed; the rest of the
              // cell falls through to the router below.
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
                        onTap: () => _editName(players[i].id),
                      ),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: layout.toolbar,
                child: _Toolbar(
                  playerCount: players.length,
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
    final roll = _rng.nextInt(20) + 1;
    await showDialog<void>(
      context: context,
      builder: (context) => _RollDialog(title: 'd20', value: '$roll'),
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: LifeTapColors.surface,
      isScrollControlled: true,
      builder: (context) =>
          _PlayerSettingsSheet(playerId: playerId, quarterTurns: quarterTurns),
    );
  }

  /// Opens an upright (never seat-rotated) dialog to rename the player. Keeping
  /// it screen-oriented — unlike the seat-rotated name label that opened it —
  /// means the field and keyboard are easy to type on. Landscape stays locked
  /// (set in main.dart); nothing here reorients when the field is focused.
  Future<void> _editName(int playerId) async {
    final current = ref.read(gameProvider).current.player(playerId).name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameEditDialog(initialName: current),
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

/// True when the player has reached a lethal threshold under the current
/// settings — used only for the knocked-out visual, never for game logic.
bool _knockedOut(PlayerState player, GameSettings settings) {
  if (!settings.autoKo) return false;
  final cmdrLethal =
      settings.commanderDamageLifeLoss &&
      player.commanderDamage.values.any((d) => d >= 21);
  return player.life <= 0 || player.poison >= 10 || cmdrLethal;
}

class _PlayerZone extends ConsumerWidget {
  const _PlayerZone({required this.player, required this.quarterTurns});

  final PlayerState player;
  final int quarterTurns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ko = _knockedOut(player, settings);
    final base = Color(player.color);
    final solid = Color.lerp(base, Colors.black, 0.6)!;
    final art = player.artUrl;

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
          if (art != null) ...[
            // Falls back to the solid color while loading or on any error, so a
            // missing/broken image never leaves the zone blank.
            Image.network(
              art,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => ColoredBox(color: solid),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : ColoredBox(color: solid),
            ),
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
                  child: Text(
                    '${player.life}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      decoration: knockedOut
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
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
                padding: const EdgeInsets.only(bottom: 10),
                child: _CounterChips(player: player),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A compact wrap of small rounded chips for the player's non-zero secondary
/// counters and commander-damage entries. Shows nothing when all are zero.
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
      for (final dmg in player.commanderDamage.entries)
        if (dmg.value > 0)
          _CounterChip(
            icon: Icons.shield,
            value: dmg.value,
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
    setState(() => _resolving = true);
    final source = ref.read(commanderArtSourceProvider);
    final art = name.isEmpty ? null : await source.artUrl(name);
    if (!mounted) return;
    ref
        .read(gameProvider.notifier)
        .dispatch(
          SetCommander(
            playerId: widget.playerId,
            commanderName: name.isEmpty ? null : name,
            artUrl: art,
          ),
        );
    setState(() => _resolving = false);
  }

  void _recolor(int color) {
    ref
        .read(gameProvider.notifier)
        .dispatch(RecolorPlayer(playerId: widget.playerId, color: color));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RotatedBox(
        quarterTurns: widget.quarterTurns,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Name'),
                onSubmitted: _submitName,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commanderController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Commander',
                  suffixIcon: _resolving
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
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
    );
  }
}

/// Upright, screen-centered rename dialog. Held deliberately at the normal
/// screen orientation (quarterTurns 0) — not rotated to the seat — with an
/// autofocused field prefilled with the current name. Confirm pops the new
/// name; an outside tap or Cancel pops null and leaves the name unchanged.
class _NameEditDialog extends StatefulWidget {
  const _NameEditDialog({required this.initialName});

  final String initialName;

  @override
  State<_NameEditDialog> createState() => _NameEditDialogState();
}

class _NameEditDialogState extends State<_NameEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LifeTapColors.surface,
      title: const Text('Player name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
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

/// The slim toolbar strip: white icon buttons plus a cyan-ringed badge showing
/// the current player count. Reset and the badge both open the settings screen.
/// Sits between the rows for 2/4/6 players and at the bottom for 3/5.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.playerCount,
    required this.onSettings,
    required this.onUndo,
    required this.onDice,
    required this.onCoin,
    required this.onHistory,
  });

  final int playerCount;
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
