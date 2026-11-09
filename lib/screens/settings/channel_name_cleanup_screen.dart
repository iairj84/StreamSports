import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/channel_name_cleanup.dart';
import '../../services/channel_names.dart';
import '../../services/playlist_manager.dart';
import '../../services/storage_service.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';

/// Settings > Channel names > Clean up names: strip the provider's padding from
/// every name in one pass, with a preview of exactly what will change.
///
/// Nothing is written until Apply, the plan skips channels the viewer named by
/// hand, and the apply is one batch of rename overrides — so Undo is a single
/// clear of those overrides and the provider's names come straight back.
class ChannelNameCleanupScreen extends StatefulWidget {
  const ChannelNameCleanupScreen({super.key});

  @override
  State<ChannelNameCleanupScreen> createState() =>
      _ChannelNameCleanupScreenState();
}

class _ChannelNameCleanupScreenState extends State<ChannelNameCleanupScreen> {
  final Set<ChannelCleanupRule> _rules = {...ChannelNameCleanup.defaults};

  /// Rows written by the last Apply, kept so Undo knows which channels to put
  /// back. Cleared by Undo, replaced by the next Apply.
  List<ChannelCleanupRow>? _applied;
  bool _busy = false;

  Future<void> _apply(ChannelCleanupPlan plan) async {
    if (_busy || plan.isEmpty) return;
    setState(() => _busy = true);
    final playlist = context.read<PlaylistManager>();
    final storage = context.read<StorageService>();
    final rows = plan.rows;
    await ChannelRenames.renameMany(
        storage, [for (final row in rows) (row.channel, row.after)]);
    if (!mounted) return;
    playlist.applyChannelNames();
    setState(() {
      _busy = false;
      _applied = rows;
    });
  }

  Future<void> _undo() async {
    final applied = _applied;
    if (_busy || applied == null) return;
    setState(() => _busy = true);
    final playlist = context.read<PlaylistManager>();
    final storage = context.read<StorageService>();
    // The plan skipped hand-picked names, so every channel it touched had no
    // override before it ran; clearing the override restores the provider name.
    await ChannelRenames.renameMany(
        storage, [for (final row in applied) (row.channel, '')]);
    if (!mounted) return;
    playlist.applyChannelNames();
    setState(() {
      _busy = false;
      _applied = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlist = context.watch<PlaylistManager>();
    final channels = playlist.visibleChannels(category: 'tv');
    final plan = ChannelNameCleanup.plan(channels, _rules);
    final applied = _applied;
    final theme = Theme.of(context);

    return SettingsScaffold(
      title: tr('Clean up channel names'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          tr('Strip the padding providers add to every name — region tags, quality markers and slot numbers. The playlist is never edited: clean names are saved as renames, so a provider update cannot undo them.'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (applied != null)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(children: [
                Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    applied.length == 1
                        ? tr('1 channel cleaned up.')
                        : tr('{n} channels cleaned up.', {'n': '${applied.length}'}),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _undo,
                  child: Text(tr('Undo')),
                ),
              ]),
            ),
          ),
        SettingsSection(title: tr('Rules'), children: [
          for (final rule in ChannelCleanupRule.values)
            SwitchListTile(
              value: _rules.contains(rule),
              title: Text(tr(rule.label)),
              subtitle: Text(tr(rule.description)),
              onChanged: _busy
                  ? null
                  : (on) => setState(() {
                        if (on) {
                          _rules.add(rule);
                        } else {
                          _rules.remove(rule);
                        }
                      }),
            ),
        ]),
        SettingsSection(title: tr('Preview'), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              plan.isEmpty
                  ? tr('Nothing to change with these rules. Try turning one back on, or rename channels by hand.')
                  : _summary(plan),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          for (final row in plan.rows.take(200))
            ListTile(
              dense: true,
              leading: Icon(Icons.label_outline,
                  color: theme.colorScheme.onSurfaceVariant),
              title: Text(row.after,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(row.before,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (plan.rows.length > 200)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  tr('Showing the first 200 of {n}.', {
                    'n': '${plan.rows.length}'
                  }),
                  style: theme.textTheme.bodySmall),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: FilledButton.icon(
            onPressed: plan.isEmpty || _busy ? null : () => _apply(plan),
            icon: const Icon(Icons.auto_fix_high),
            label: Text(_busy
                ? tr('Applying…')
                : plan.isEmpty
                    ? tr('Nothing to apply')
                    : tr('Apply to {n} channels',
                        {'n': '${plan.rows.length}'})),
          ),
        ),
        Text(
          tr('Undo stays available on this screen until you leave it or apply again.'),
          style: theme.textTheme.bodySmall,
        ),
      ]),
    );
  }

  String _summary(ChannelCleanupPlan plan) {
    final changed = plan.rows.length == 1
        ? tr('1 of {n} channels changes.', {'n': '${plan.examined}'})
        : tr('{changed} of {n} channels change.', {
            'changed': '${plan.rows.length}',
            'n': '${plan.examined}',
          });
    if (plan.skippedRenamed == 0) return changed;
    return '$changed '
        '${tr('{n} named by hand are left alone.', {'n': '${plan.skippedRenamed}'})}';
  }
}
