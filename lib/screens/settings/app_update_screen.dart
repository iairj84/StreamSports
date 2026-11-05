import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/app_update_service.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';

/// Manual update path: check, download and install a newer published build.
/// The same service drives the startup prompt; this screen is where a viewer
/// goes when they want an update now.
class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final update = context.read<AppUpdateService>();
      update.load();
      if (!update.checked) update.check(manual: true);
    });
  }

  Future<void> _check() async {
    final update = context.read<AppUpdateService>();
    setState(() => _message = null);
    await update.check(manual: true);
  }

  Future<void> _download() async {
    final update = context.read<AppUpdateService>();
    final file = await update.download();
    if (!mounted) return;
    setState(() => _message = file == null
        ? update.error
        : tr('Downloaded. Install it to finish updating.'));
  }

  Future<void> _install() async {
    final update = context.read<AppUpdateService>();
    final result = await update.install();
    if (!mounted) return;
    switch (result) {
      case AppInstallResult.started:
        setState(() => _message = tr(
            'The installer is open. Confirm the update to finish.'));
      case AppInstallResult.needsPermission:
        await update.openInstallPermissionSettings();
        if (!mounted) return;
        setState(() => _message = tr(
            'Allow this app to install updates, then press Install again.'));
      case AppInstallResult.missingFile:
        setState(() => _message = tr('Download the update again.'));
      case AppInstallResult.failed:
        setState(() => _message =
            update.error ?? tr('The update could not be installed.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = context.watch<AppUpdateService>();
    final release = update.available;
    final busy = update.checking || update.downloading;
    final scheme = Theme.of(context).colorScheme;

    final installed = SettingsSection(
      title: tr('Installed build'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Version {v}', {'v': update.currentLabel}),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(tr('Updates come from this app\'s own releases.'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(update.checking
                    ? tr('Checking…')
                    : tr('Check for updates')),
                onPressed: busy ? null : _check,
              ),
            ],
          ),
        ),
      ],
    );

    final status = SettingsSection(
      title: tr('Status'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (update.error != null)
                Text(update.error!,
                    style: TextStyle(color: scheme.error, fontSize: 13))
              else if (release == null)
                Text(
                    update.checked
                        ? tr('This device is running the newest build.')
                        : tr('Tap Check for updates to look for a newer build.'),
                    style: Theme.of(context).textTheme.bodySmall)
              else ...[
                Text(tr('Available: {v}', {'v': release.label}),
                    style: Theme.of(context).textTheme.bodyMedium),
                if (release.sizeLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(tr('Download size: {size}',
                            {'size': release.sizeLabel}),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (release.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                          child: Text(release.notes,
                              style: Theme.of(context).textTheme.bodySmall)),
                    ),
                  ),
                if (update.downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                      value: update.downloadProgress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3)),
                  const SizedBox(height: 6),
                  Text(
                      tr('Downloading… {p}%', {
                        'p': ((update.downloadProgress ?? 0) * 100).floor(),
                      }),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                if (!update.hasDownload)
                  FilledButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(tr('Download update')),
                    onPressed: busy ? null : _download,
                  )
                else
                  FilledButton.icon(
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: Text(tr('Install update')),
                    onPressed: busy ? null : _install,
                  ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: busy ? null : () async {
                    await update.skipCurrent();
                    if (mounted) {
                      setState(() => _message =
                          tr('This build will not be offered again.'));
                    }
                  },
                  child: Text(tr('Skip this build')),
                ),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_message!,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ],
    );

    return SettingsScaffold(
      title: tr('App updates'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [installed, status],
      ),
    );
  }
}
