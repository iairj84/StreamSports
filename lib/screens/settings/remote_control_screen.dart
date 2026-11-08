import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../services/remote_controls.dart';
import '../../utils/tv_theme.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/tv_menu_tile.dart';

/// Settings > Remote control.
///
/// Two halves, both useful on their own: a plain-language guide to what the
/// buttons already do (the part that costs nothing and answers the common
/// "what does the coloured button do" question), and remapping for the spare
/// buttons. Nothing is remapped by default — see [RemoteControls].
class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  RemoteControls get _controls => RemoteControls.instance;

  static const _icons = {
    RemoteAction.live: Icons.live_tv,
    RemoteAction.sports: Icons.sports_soccer,
    RemoteAction.search: Icons.search,
    RemoteAction.multiview: Icons.grid_view,
    RemoteAction.movies: Icons.movie_outlined,
    RemoteAction.shows: Icons.video_library_outlined,
    RemoteAction.settings: Icons.settings_outlined,
  };

  Future<void> _capture(RemoteAction action) async {
    final captured = await showDialog<_Captured>(
        context: context,
        builder: (_) => _CaptureDialog(
            action: action, current: _controls.bindingForAction(action)));
    if (captured == null || !mounted) return;
    final keyId = captured.keyId;
    if (keyId == null) {
      _controls.unbind(action);
    } else {
      _controls.bind(keyId, action, label: captured.label ?? action.label);
    }
  }

  static const _playbackIcons = {
    PlaybackAction.off: Icons.block,
    PlaybackAction.scores: Icons.scoreboard_outlined,
    PlaybackAction.channelList: Icons.view_list_outlined,
    PlaybackAction.lastChannel: Icons.history,
    PlaybackAction.channelUp: Icons.keyboard_arrow_up,
    PlaybackAction.channelDown: Icons.keyboard_arrow_down,
    PlaybackAction.streamInfo: Icons.analytics_outlined,
    PlaybackAction.infoCard: Icons.info_outline,
    PlaybackAction.playPause: Icons.play_arrow,
    PlaybackAction.topBar: Icons.vertical_align_top,
    PlaybackAction.controls: Icons.vertical_align_bottom,
    PlaybackAction.backToGuide: Icons.keyboard_return,
  };

  Future<void> _pickPlayback(PlaybackKey key) async {
    final current = _controls.playbackActionFor(key);
    final picked = await showDialog<PlaybackAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(tr('{key} does', {'key': tr(key.label)})),
        children: [
          for (final action in PlaybackAction.values)
            TvMenuTile(
              icon: _playbackIcons[action],
              autofocus: action == current,
              title: tr(action.label),
              trailing: action == current
                  ? Icon(Icons.check,
                      color: Theme.of(dialogContext).colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(action),
            ),
        ],
      ),
    );
    if (picked != null) _controls.bindPlayback(key, picked);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(tr('Reset remapped buttons?')),
              content: Text(tr(
                  'Every remapped button goes back to doing what it did before.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(tr('Reset'))),
                TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(tr('Cancel'))),
              ],
            ));
    if (ok == true) _controls.reset();
  }

  @override
  Widget build(BuildContext context) {
    return withTvThemeIfNeeded(
        context,
        (context) => SettingsScaffold(
              title: tr('Remote control'),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  SettingsSection(title: tr('When watching'), children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                          tr(
                              'Each player button can do any of these. The ones shown are what they do today.'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    AnimatedBuilder(
                        animation: _controls,
                        builder: (context, _) => Column(children: [
                              for (final key in PlaybackKey.values)
                                TvMenuTile(
                                  icon: _playbackIcons[_controls
                                          .playbackActionFor(key)] ??
                                      Icons.radio_button_checked,
                                  title: tr(key.label),
                                  subtitle: tr(_controls
                                      .playbackActionFor(key)
                                      .label),
                                  onTap: () => _pickPlayback(key),
                                ),
                            ])),
                    TvMenuTile(
                      icon: Icons.restart_alt,
                      title: tr('Reset player buttons'),
                      subtitle: tr('Back to the shipped defaults'),
                      enabled: !_controls.playbackIsDefault,
                      onTap: _controls.resetPlayback,
                    ),
                  ]),
                  SettingsSection(
                      title: tr('What your remote does'),
                      children: [
                        _Reference(
                            icon: Icons.unfold_more,
                            title: tr('Up and down'),
                            detail: tr(
                                'Moves through channels in Live TV, rows in the guide, and lines in a menu.')),
                        _Reference(
                            icon: Icons.unfold_less,
                            title: tr('Left and right'),
                            detail: tr(
                                'Steps between categories and channels, and through time in the guide. In the player, Left opens the channel list and Right returns to the last channel — both can be changed above.')),
                        _Reference(
                            icon: Icons.radio_button_checked,
                            title: tr('OK / Select'),
                            detail: tr(
                                'Watches the highlighted channel or opens the item. Hold it on a channel for that channel’s tools.')),
                        _Reference(
                            icon: Icons.arrow_back,
                            title: tr('Back'),
                            detail: tr(
                                'Up one level, and out of the player back to the guide.'),
                        ),
                        _Reference(
                            icon: Icons.fullscreen,
                            title: tr('Right at the end of the row'),
                            detail: tr(
                                'Jumps straight to full screen on whatever is already playing. Hold Right for the resume hint.'),
                        ),
                        _Reference(
                            icon: Icons.play_arrow,
                            title: tr('Play / pause'),
                            detail: tr(
                                'Starts or pauses the player; in Live TV it is a spare button you can remap below.')),
                        _Reference(
                            icon: Icons.palette_outlined,
                            title: tr('Coloured and extra buttons'),
                            detail: tr(
                                'Most remotes send keys the app has no default for. If a button does nothing, remap it below.'),
                        ),
                        _Reference(
                            icon: Icons.info_outline,
                            title: tr('Home, volume and power'),
                            detail: tr(
                                'These are handled by the TV itself and never reach the app, so they cannot be remapped.'),
                        ),
                      ]),
                  SettingsSection(
                      title: tr('Extra buttons'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                              tr(
                                  'Only for remotes with spare buttons beyond the D-pad. Choose an action, then press the button. These work in Live TV.'),
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        AnimatedBuilder(
                            animation: _controls,
                            builder: (context, _) => Column(children: [
                                  for (final action in RemoteAction.values)
                                    TvMenuTile(
                                      icon: _icons[action],
                                      title: tr(action.label),
                                      subtitle: _controls
                                                  .bindingForAction(action) ==
                                              null
                                          ? tr('Not remapped')
                                          : tr('{key}', {
                                              'key': _controls
                                                  .bindingForAction(action)!
                                                  .label
                                            }),
                                      onTap: () => _capture(action),
                                    ),
                                ])),
                      ]),
                  SettingsSection(
                      title: tr('Start over'),
                      children: [
                        TvMenuTile(
                          icon: Icons.restart_alt,
                          title: tr('Reset remapped buttons'),
                          subtitle: tr('Every button back to its default'),
                          enabled: !_controls.isEmpty,
                          onTap: _reset,
                        ),
                      ]),
                ],
              ),
            ));
  }
}

/// One line of the guide: a button and what it does.
///
/// Focusable even though it does nothing when opened. Without that, the remote
/// can never read the guide: traversal skips straight from the row above it to
/// the next section's tiles, and the list scrolls this text past the screen on
/// the way. Being focusable also gives each line a highlight, which is what
/// tells the viewer where the remote is in a wall of prose.
class _Reference extends StatefulWidget {
  const _Reference(
      {required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  State<_Reference> createState() => _ReferenceState();
}

class _ReferenceState extends State<_Reference> {
  bool _focused = false;

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      Scrollable.ensureVisible(context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Focus(
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) _reveal();
        },
        child: ColoredBox(
          color: _focused
              ? scheme.primaryContainer.withValues(alpha: .55)
              : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(widget.icon,
                  size: 20,
                  color: _focused ? scheme.onPrimaryContainer : scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _focused ? scheme.onPrimaryContainer : null)),
                    const SizedBox(height: 2),
                    Text(widget.detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _focused
                                ? scheme.onPrimaryContainer.withValues(alpha: .85)
                                : null)),
                  ])),
            ]),
          ),
        ),
      ),
    );
  }
}

/// What the capture dialog hands back: a key to bind, or [keyId] null to
/// remove the action's current button.
class _Captured {
  const _Captured(this.keyId, this.label);

  final int? keyId;
  final String? label;
}

class _CaptureDialog extends StatefulWidget {
  const _CaptureDialog({required this.action, required this.current});

  final RemoteAction action;
  final RemoteBinding? current;

  @override
  State<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<_CaptureDialog> {
  String? _refused;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (isReservedRemoteKey(event)) {
      setState(() => _refused = 'That button is used for navigation. '
          'Try a coloured, media or unused button.');
      return KeyEventResult.handled;
    }
    Navigator.of(context)
        .pop(_Captured(event.physicalKey.usbHidUsage, remoteKeyLabel(event)));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('{action}: press a button',
            {'action': tr(widget.action.label)})),
        content: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Text(
              _refused ??
                  (widget.current == null
                      ? tr('Listening for a button. Back cancels.')
                      : tr('Now on {key}. Press another button, or Remove.',
                          {'key': widget.current!.label})),
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        actions: [
          if (widget.current != null)
            TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _Captured(null, null)),
                child: Text(tr('Remove'))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Cancel'))),
        ],
      );
}
