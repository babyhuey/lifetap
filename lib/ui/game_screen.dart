import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../game/game_events.dart';
import '../game/game_state.dart';
import '../game/game_notifier.dart';
import '../touch/pointer_router.dart';

/// Height reserved at the bottom for the toolbar so player zones never sit
/// under it (and toolbar touches never route into a zone).
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

  @override
  void initState() {
    super.initState();
    _router = PointerRouter(onResult: _onResult);
    _enableWakelock();
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final zoneArea = Size(size.width, size.height - _toolbarHeight);
          final rects = _zoneRects(players.length, zoneArea);
          _router.zones = rects;

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
                            quarterTurns: _zoneQuarterTurns(i, players.length),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _toolbarHeight,
                child: _Toolbar(
                  onNewGame: _showNewGameDialog,
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

  Future<void> _showNewGameDialog() async {
    final choice = await showDialog<({int count, int life})>(
      context: context,
      builder: (context) => const _NewGameDialog(),
    );
    if (choice == null) return;
    ref.read(gameProvider.notifier).newGame(choice.count, choice.life);
  }

  Future<void> _showDice() async {
    final roll = _rng.nextInt(20) + 1;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('d20'),
        content: Text('$roll', style: const TextStyle(fontSize: 48)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCoin() async {
    final heads = _rng.nextBool();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coin flip'),
        content: Text(
          heads ? 'Heads' : 'Tails',
          style: const TextStyle(fontSize: 32),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHistory() async {
    final lines = ref.read(gameProvider.notifier).historyLines();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = lines.length - 1; i >= 0; i--)
              ListTile(dense: true, title: Text(lines[i])),
          ],
        ),
      ),
    );
  }
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

/// Top-row seats face across the table, so rotate them 180 degrees.
int _zoneQuarterTurns(int index, int count) {
  final cols = count <= 2 ? 1 : 2;
  return (index ~/ cols) == 0 ? 2 : 0;
}

class _PlayerZone extends StatelessWidget {
  const _PlayerZone({required this.player, required this.quarterTurns});

  final PlayerState player;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final base = Color(player.color);
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(base, Colors.black, 0.6),
          border: Border.all(color: base, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                player.name,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              Text(
                '${player.life}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 84,
                  fontWeight: FontWeight.bold,
                  decoration: player.isDead
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
              Text(
                'PSN ${player.poison}   NRG ${player.energy}   '
                'EXP ${player.experience}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onNewGame,
    required this.onUndo,
    required this.onDice,
    required this.onCoin,
    required this.onHistory,
  });

  final VoidCallback onNewGame;
  final VoidCallback onUndo;
  final VoidCallback onDice;
  final VoidCallback onCoin;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'New game',
            onPressed: onNewGame,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: onUndo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Dice',
            onPressed: onDice,
            icon: const Icon(Icons.casino),
          ),
          IconButton(
            tooltip: 'Coin flip',
            onPressed: onCoin,
            icon: const Icon(Icons.monetization_on),
          ),
          IconButton(
            tooltip: 'History',
            onPressed: onHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
    );
  }
}

class _NewGameDialog extends StatefulWidget {
  const _NewGameDialog();

  @override
  State<_NewGameDialog> createState() => _NewGameDialogState();
}

class _NewGameDialogState extends State<_NewGameDialog> {
  int _count = 2;
  int _life = 20;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New game'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Players'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [2, 3, 4, 5, 6])
                ChoiceChip(
                  label: Text('$n'),
                  selected: _count == n,
                  onSelected: (_) => setState(() => _count = n),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Starting life'),
          Wrap(
            spacing: 8,
            children: [
              for (final l in [20, 30, 40])
                ChoiceChip(
                  label: Text('$l'),
                  selected: _life == l,
                  onSelected: (_) => setState(() => _life = l),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((count: _count, life: _life)),
          child: const Text('Start'),
        ),
      ],
    );
  }
}
