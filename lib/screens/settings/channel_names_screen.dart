import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/channel.dart';
import '../../services/channel_names.dart';
import '../../services/playlist_manager.dart';
import '../../services/storage_service.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/tv_text_field_gate.dart';

/// Settings > Channel names: rename a channel once and every screen uses that
/// name — the guide, Sports matching, the channel picker and the player. The
/// provider's playlist is untouched, so a refresh cannot undo a rename.
class ChannelNamesScreen extends StatefulWidget {
  const ChannelNamesScreen({super.key});

  @override
  State<ChannelNamesScreen> createState() => _ChannelNamesScreenState();
}

class _ChannelNamesScreenState extends State<ChannelNamesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'channel-names-search');

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _rename(Channel channel) async {
    final controller = TextEditingController(text: channel.name);
    final providerName = channel.originalName;
    final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => FocusNodeOwner(
              builder: (context, node) => AlertDialog(
                title: Text(tr('Rename channel')),
                content: TvTextFieldGate(
                  focusNode: node,
                  builder: (context, readOnly) => TextField(
                    controller: controller,
                    focusNode: node,
                    readOnly: readOnly,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: tr('Name shown in StreamSports'),
                      helperText: providerName == null
                          ? tr('The provider calls this {name}', {
                              'name': channel.name,
                            })
                          : tr('The provider calls this {name}', {
                              'name': providerName,
                            }),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(tr('Cancel'))),
                  if (providerName != null)
                    TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(''),
                        child: Text(tr('Use provider name'))),
                  FilledButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(controller.text),
                      child: Text(tr('Save'))),
                ],
              ),
            ));
    controller.dispose();
    if (name == null || !mounted) return;
    final changed = await ChannelRenames.rename(
        context.read<StorageService>(), channel, name);
    if (!changed || !mounted) return;
    context.read<PlaylistManager>().applyChannelNames();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playlist = context.watch<PlaylistManager>();
    final channels = playlist.visibleChannels(category: 'tv');
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? channels
        : channels
            .where((c) =>
                c.name.toLowerCase().contains(query) ||
                c.group.toLowerCase().contains(query))
            .toList();

    return SettingsScaffold(
      title: tr('Channel names'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              tr('Rename a channel and every screen uses the new name: the guide, Sports matching, the channel picker and the player. Your playlist is never edited, so updates cannot undo it.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TvTextFieldGate(
              focusNode: _searchFocus,
              builder: (context, readOnly) => TextField(
                controller: _search,
                focusNode: _searchFocus,
                readOnly: readOnly,
                decoration: InputDecoration(
                  labelText: tr('Search your channels'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(tr('No channels found.')))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final channel = filtered[i];
                      final was = channel.originalName;
                      final playlistName =
                          playlist.playlistNameFor(channel.playlistId);
                      return ListTile(
                        title: Text(channel.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            was == null
                                ? '${channel.group} · $playlistName'
                                : tr('{group} · {p} · was {was}', {
                                    'group': channel.group,
                                    'p': playlistName,
                                    'was': was,
                                  }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: tr('Rename'),
                          onPressed: () => _rename(channel),
                        ),
                        onTap: () => _rename(channel),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
