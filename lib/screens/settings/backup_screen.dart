import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/backup_service.dart';
import '../../services/playlist_manager.dart';
import '../../services/storage_service.dart';
import '../../widgets/settings_scaffold.dart';
import '../../widgets/settings_section.dart';

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Snapshots of this device's configuration, and putting one back.
///
/// A transfer and a restore both replace the device's playlists, settings,
/// sports picks and lists, and nothing else offers an undo for that. Backups
/// stay in the app's own folder, so they survive a bad change but not an
/// uninstall — moving a configuration to another box is what the transfer
/// screen is for.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<BackupFile> _backups = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _result;

  StorageService get _storage => context.read<StorageService>();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final backups = await BackupService.list();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'The backups on this device could not be read.';
      });
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final backup = await BackupService.create(_storage);
      await _reload();
      if (!mounted) return;
      setState(() => _result = 'Backup saved: ${_describe(backup)}.');
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = 'The backup could not be saved. Check that this device has free storage.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupFile backup) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final manager = context.read<PlaylistManager>();
      final report = await BackupService.restore(_storage, backup);
      // The playlists just changed underneath the loaded channels, so reload
      // them here instead of asking the viewer to close and reopen the app.
      await manager.reloadFromStorage();
      await _reload();
      if (!mounted) return;
      setState(() => _result =
          '${report.values} settings were restored from ${_describe(backup)}, and the playlists were reloaded.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is StateError
          ? e.message
          : 'The backup could not be restored.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupFile backup) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await BackupService.delete(backup);
      await _reload();
      if (!mounted) return;
      setState(() => _result = 'Backup deleted.');
    } catch (e) {
      if (mounted) setState(() => _error = 'That backup could not be deleted.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One dialog for the row: restoring replaces everything, so it is never a
  /// single tap.
  Future<void> _open(BackupFile backup) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Backup from ${_describe(backup)}')),
        content: Text(tr(
            'Restoring replaces this device’s playlists, settings, sports picks, favorites, channel links and channel names with the copy in this backup. Anything saved since then is lost.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('delete'),
              child: Text(tr('Delete'))),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('restore'),
              child: Text(tr('Restore'))),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'restore') await _restore(backup);
    if (choice == 'delete') await _delete(backup);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: tr('Backup & restore'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Results and failures first: below the list they read as nothing
        // happening.
        if (_result != null)
          _NoticeCard(
              message: _result!,
              icon: Icons.check_circle_outline,
              background: Theme.of(context).colorScheme.primaryContainer,
              foreground: Theme.of(context).colorScheme.onPrimaryContainer),
        if (_error != null)
          _NoticeCard(
              message: _error!,
              icon: Icons.error_outline,
              background: Theme.of(context).colorScheme.errorContainer,
              foreground: Theme.of(context).colorScheme.onErrorContainer),
        SettingsSection(title: tr('This device'), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                tr('A backup is a copy of this device’s playlists, settings, sports picks, favorites, channel links and channel names. It is kept inside the app, so it outlasts a mistake but not an uninstall.'),
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: Text(tr('Create a backup now')),
            subtitle: Text(tr(
                'Up to ${BackupService.keep} backups are kept; older ones are removed')),
            enabled: !_busy,
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _create,
          ),
        ]),
        SettingsSection(title: tr('Saved backups'), children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_backups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  tr('No backups yet. Create one before changing playlists or settings you may want back.'),
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            for (final backup in _backups)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(_describe(backup)),
                subtitle: Text(tr('Restore or delete this backup')),
                enabled: !_busy,
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _open(backup),
              ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
              tr('To move a configuration to another device, use Transfer to another device. That copy travels encrypted over your own Wi-Fi and carries the same data.'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}

String _describe(BackupFile backup) {
  final time = backup.createdAt;
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.day} ${_months[time.month - 1]} ${time.year} at $hour:$minute'
      ' · ${_size(backup.bytes)}';
}

String _size(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes bytes';
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(
      {required this.message,
      required this.icon,
      required this.background,
      required this.foreground});

  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: foreground)),
          ),
        ]),
      );
}
