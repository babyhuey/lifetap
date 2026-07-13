import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/game_notifier.dart';
import 'theme.dart';

/// Selectable player counts and starting-life presets shown on the settings
/// screen. Starting life covers the common Commander/60-card formats.
const List<int> playerCountOptions = [2, 3, 4, 5, 6];
const List<int> startingLifeOptions = [20, 25, 30, 40, 60];

/// App-level gameplay settings, independent of the event-sourced game session
/// so toggling one never rewrites game history or resets the current match.
@immutable
class GameSettings {
  const GameSettings({
    this.commanderDamageLifeLoss = true,
    this.autoKo = true,
    this.inAppKeyboard = true,
  });

  /// When true, commander damage also subtracts life (the default rule).
  final bool commanderDamageLifeLoss;

  /// When true, a player who has hit a lethal threshold is shown knocked out.
  final bool autoKo;

  /// When true, the rename editor uses a small seat-rotated on-screen keyboard
  /// instead of the OS keyboard (which the OS can't rotate to face a side seat).
  final bool inAppKeyboard;

  GameSettings copyWith({
    bool? commanderDamageLifeLoss,
    bool? autoKo,
    bool? inAppKeyboard,
  }) => GameSettings(
    commanderDamageLifeLoss:
        commanderDamageLifeLoss ?? this.commanderDamageLifeLoss,
    autoKo: autoKo ?? this.autoKo,
    inAppKeyboard: inAppKeyboard ?? this.inAppKeyboard,
  );
}

class SettingsNotifier extends Notifier<GameSettings> {
  @override
  GameSettings build() => const GameSettings();

  void setCommanderDamageLifeLoss(bool value) =>
      state = state.copyWith(commanderDamageLifeLoss: value);

  void setAutoKo(bool value) => state = state.copyWith(autoKo: value);

  void setInAppKeyboard(bool value) =>
      state = state.copyWith(inAppKeyboard: value);
}

final settingsProvider = NotifierProvider<SettingsNotifier, GameSettings>(
  SettingsNotifier.new,
);

/// Full-screen dark "Settings" / new-game screen: pick player count and
/// starting life as cyan-ringed chips, flip the gameplay toggles, then Start.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late int _count;
  late int _life;

  @override
  void initState() {
    super.initState();
    final current = ref.read(gameProvider).current;
    _count = current.playerCount;
    _life = startingLifeOptions.contains(current.startingLife)
        ? current.startingLife
        : 40;
  }

  void _start() {
    ref.read(gameProvider.notifier).newGame(_count, _life);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LifeTapColors.background,
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            const _SectionHeader('Game Setup'),
            const SizedBox(height: 16),
            const _RowLabel('Players'),
            const SizedBox(height: 10),
            _ChipRow(
              options: playerCountOptions,
              selected: _count,
              onSelected: (n) => setState(() => _count = n),
            ),
            const SizedBox(height: 20),
            const _RowLabel('Starting life'),
            const SizedBox(height: 10),
            _ChipRow(
              options: startingLifeOptions,
              selected: _life,
              onSelected: (n) => setState(() => _life = n),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LifeTapColors.accent,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _start,
                child: const Text('Start game'),
              ),
            ),
            const SizedBox(height: 32),
            const _SectionHeader('Gameplay'),
            _ToggleRow(
              label: 'Commander damage life loss',
              value: settings.commanderDamageLifeLoss,
              onChanged: ref
                  .read(settingsProvider.notifier)
                  .setCommanderDamageLifeLoss,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'In-app keyboard',
                style: TextStyle(
                  color: LifeTapColors.textPrimary,
                  fontSize: 15,
                ),
              ),
              subtitle: const Text(
                'Type names with a keyboard that faces your seat (side seats). '
                "Off = your device's keyboard.",
                style: TextStyle(
                  color: LifeTapColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              value: settings.inAppKeyboard,
              onChanged: ref.read(settingsProvider.notifier).setInAppKeyboard,
              activeTrackColor: LifeTapColors.accent,
              activeThumbColor: Colors.black,
            ),
            _ToggleRow(
              label: 'Auto-KO',
              value: settings.autoKo,
              onChanged: ref.read(settingsProvider.notifier).setAutoKo,
            ),
          ],
        ),
      ),
    );
  }
}

/// A secondary-text section title with a hairline rule under it.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: LifeTapColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Divider(color: LifeTapColors.divider, height: 1),
      ],
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: LifeTapColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A single-select row of circular chips (player counts or life presets).
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<int> options;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final n in options)
          _CircleChip(
            value: n,
            selected: n == selected,
            onTap: () => onSelected(n),
          ),
      ],
    );
  }
}

class _CircleChip extends StatelessWidget {
  const _CircleChip({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.transparent : LifeTapColors.chipUnselected,
          border: selected
              ? Border.all(color: LifeTapColors.accent, width: 2)
              : null,
        ),
        child: Text(
          '$value',
          style: TextStyle(
            color: selected ? LifeTapColors.accent : LifeTapColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: LifeTapColors.textPrimary,
                fontSize: 15,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: LifeTapColors.accent,
            activeThumbColor: Colors.black,
          ),
        ],
      ),
    );
  }
}
