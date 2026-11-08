import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/launcher_icon_export.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/tv_menu_tile.dart';

/// Hands the cut-out logos to Projectivy (or any launcher that takes a
/// picture per app) without a computer in the middle.
class LauncherIconScreen extends StatefulWidget {
  const LauncherIconScreen({super.key, this.export});

  /// Injection point for tests; the app builds the real one.
  final LauncherIconExport? export;

  @override
  State<LauncherIconScreen> createState() => _LauncherIconScreenState();
}

class _LauncherIconScreenState extends State<LauncherIconScreen> {
  late final LauncherIconExport _export = widget.export ?? LauncherIconExport();
  String? _saving;
  String? _saved;

  String _message(LauncherIconSave outcome) => switch (outcome) {
        LauncherIconSave.saved =>
          tr('Saved to Pictures/StreamSports. Choose it in your launcher.'),
        LauncherIconSave.permissionDenied =>
          tr('Saving needs storage permission on this Android version.'),
        LauncherIconSave.unavailable =>
          tr('Saving to the device works in the Android app.'),
        LauncherIconSave.failed => tr('The file could not be saved.'),
      };

  Future<void> _save(LauncherIconArt art) async {
    if (_saving != null) return;
    setState(() => _saving = art.fileName);
    final outcome = await _export.save(art);
    if (!mounted) return;
    setState(() {
      _saving = null;
      _saved = outcome == LauncherIconSave.saved ? art.fileName : null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_message(outcome))));
  }

  Widget _trailing(BuildContext context, LauncherIconArt art) {
    if (_saving == art.fileName) {
      return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_saved == art.fileName) {
      return Icon(Icons.check_circle_outline,
          size: 18, color: Theme.of(context).colorScheme.primary);
    }
    return Icon(Icons.download_outlined,
        size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: tr('Launcher icon'),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SettingsSection(
              title: tr('Projectivy and other launchers'),
              children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        tr('Projectivy keeps its own picture for each app, and its chooser only offers pictures already on this device. Save one below, then set it per app with "From picture". In Projectivy, turn off Settings > Appearance > Categories > Tint custom icons so the colors are left alone.'),
                        style: Theme.of(context).textTheme.bodySmall)),
              ]),
          SettingsSection(title: tr('Save artwork'), children: [
            for (final art in launcherIconArt)
              TvMenuTile(
                  icon: Icons.image_outlined,
                  title: tr(art.title),
                  subtitle: _saving == art.fileName
                      ? tr('Saving...')
                      : tr(art.subtitle),
                  trailing: _trailing(context, art),
                  onTap: () => _save(art)),
          ]),
        ]),
      );
}
